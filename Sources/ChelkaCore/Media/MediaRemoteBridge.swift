import Foundation

public struct AdapterPaths {
    public let script: URL
    public let framework: URL

    public init(script: URL, framework: URL) {
        self.script = script
        self.framework = framework
    }

    public static func bundled(in bundle: Bundle) -> AdapterPaths? {
        guard let resources = bundle.resourceURL else { return nil }
        let script = resources.appendingPathComponent("mediaremote-adapter.pl")
        let framework = resources.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path) else { return nil }
        return AdapterPaths(script: script, framework: framework)
    }

    public static func developmentTree(projectRoot: URL) -> AdapterPaths {
        AdapterPaths(
            script: projectRoot.appendingPathComponent("vendor/mediaremote-adapter/bin/mediaremote-adapter.pl"),
            framework: projectRoot.appendingPathComponent("vendor/build/MediaRemoteAdapter.framework"))
    }
}

/// Один долгоживущий процесс на чтение потока плюс короткие вызовы на команды.
/// Обход энтайтлмента macOS 15.4+: perl уже энтайтлен, поэтому фреймворк грузит он.
public final class MediaRemoteBridge: MediaSource, @unchecked Sendable {
    public var onState: ((NowPlaying) -> Void)?
    public var onUnavailable: (() -> Void)?

    private let paths: AdapterPaths
    private var process: Process?
    private var pipe: Pipe?
    private var state = NowPlaying.empty
    private var buffer = LineBuffer()
    private var restartDelay: TimeInterval = 1
    private var stopped = false

    public init(paths: AdapterPaths) { self.paths = paths }

    public func start() {
        stopped = false
        launch()
    }

    public func stop() {
        stopped = true
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        pipe = nil
    }

    public func send(_ command: MediaCommand) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [paths.script.path, paths.framework.path, "send", String(command.rawValue)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    private func launch() {
        let p = Process()
        let newPipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [paths.script.path, paths.framework.path, "stream"]
        p.standardOutput = newPipe
        p.standardError = FileHandle.nullDevice

        newPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.consume(chunk)
        }

        p.terminationHandler = { [weak self] _ in
            // На EOF дескриптор остаётся «готов к чтению» и без явного снятия
            // обработчик будет вызываться в цикле бесконечно после смерти процесса.
            newPipe.fileHandleForReading.readabilityHandler = nil
            guard let self, !self.stopped else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.restartDelay) {
                self.restartDelay = min(self.restartDelay * 2, 30)
                self.launch()
            }
        }

        do {
            try p.run()
            process = p
            pipe = newPipe
            restartDelay = 1
        } catch {
            DispatchQueue.main.async { [weak self] in self?.onUnavailable?() }
        }
    }

    private func consume(_ chunk: Data) {
        let lines = buffer.appending(chunk)
        guard !lines.isEmpty else { return }
        for line in lines {
            guard let parsed = NowPlayingLine.parse(line) else { continue }
            state = state.applying(parsed)
        }
        let snapshot = state
        DispatchQueue.main.async { [weak self] in self?.onState?(snapshot) }
    }
}
