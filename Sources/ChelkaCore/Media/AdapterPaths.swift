import Foundation

/// Где лежит адаптер: скрипт и фреймворк рядом с ним.
public struct AdapterPaths: Sendable {
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

    /// Что не так с путями — или `nil`, если всё в порядке.
    ///
    /// Проверка существования файла отдана параметром: так её видно в тесте, и
    /// так она не зависит от того, что сейчас лежит на диске у запускающего.
    public func problem(fileExists: (String) -> Bool = {
        FileManager.default.fileExists(atPath: $0)
    }) -> AdapterPathProblem? {
        // Абсолютность проверяется ПЕРВОЙ и отдельно. Замерено на живой машине:
        // адаптер грузится только по абсолютному пути к фреймворку, с
        // относительным perl падает с «Failed to load framework». А проверка
        // существования относительный путь разрешит от текущего каталога
        // процесса — то есть из дерева сборки файл «найдётся», и поломка
        // прошла бы дальше под видом «поток падает сразу».
        if let relative = [script.path, framework.path].first(where: { !$0.hasPrefix("/") }) {
            return .relativePath(relative)
        }
        // Отсутствующий адаптер даёт коварный случай: сам perl на месте, запуск
        // «удаётся», а процесс умирает мгновенно. Без этой проверки приложение
        // молча дёргало бы его вечно, ни разу не сказав, что плеера нет.
        if !fileExists(script.path) { return .scriptMissing(script.path) }
        if !fileExists(framework.path) { return .frameworkMissing(framework.path) }
        return nil
    }
}

/// Беда с путями к адаптеру, сформулированная так, чтобы строчку в логе можно
/// было прочитать и понять, что делать.
public enum AdapterPathProblem: Equatable, Sendable {
    /// Путь не абсолютный. Отдельный случай, а не «не найден»: файл по такому
    /// пути как раз найдётся — от текущего каталога процесса, — а perl потом
    /// откажется грузить фреймворк, и причина будет выглядеть как случайный
    /// обрыв потока.
    case relativePath(String)
    case scriptMissing(String)
    case frameworkMissing(String)

    public var message: String {
        switch self {
        case .relativePath(let path):
            return "путь к адаптеру плеера не абсолютный, perl не сможет загрузить фреймворк: \(path)"
        case .scriptMissing(let path):
            return "скрипт адаптера плеера не найден: \(path)"
        case .frameworkMissing(let path):
            return "фреймворк адаптера плеера не найден (не собран?): \(path)"
        }
    }
}
