import AppKit
import Foundation

public struct CaptureResult: Equatable {
    public let store: HistoryStore
    public let inserted: ClipItem?
    public let evictedBlobNames: [String]
}

public struct ClipboardCapture {
    private let rules: IgnoreRules
    private let blobs: BlobStore

    public init(rules: IgnoreRules, blobs: BlobStore) {
        self.rules = rules
        self.blobs = blobs
    }

    public func capture(_ snapshot: PasteboardSnapshot,
                        into store: HistoryStore,
                        now: Date) -> CaptureResult {
        let decision = rules.decide(types: snapshot.types,
                                    sourceBundleID: snapshot.sourceBundleID,
                                    byteCount: snapshot.byteCount)
        guard decision.shouldStore, let kind = makeKind(snapshot) else {
            return CaptureResult(store: store, inserted: nil, evictedBlobNames: [])
        }

        let item = ClipItem(id: UUID(), kind: kind,
                            sourceAppBundleID: snapshot.sourceBundleID,
                            createdAt: now,
                            contentHash: hash(for: snapshot, kind: kind),
                            isPinned: false)
        let next = store.inserting(item)
        return CaptureResult(store: next,
                             inserted: item,
                             evictedBlobNames: next.evictedBlobNames(comparedTo: store))
    }

    private func makeKind(_ s: PasteboardSnapshot) -> ClipItem.Kind? {
        if let data = s.imageData, let ext = s.imageExtension {
            guard let name = try? blobs.write(data, extension: ext) else { return nil }
            let size = NSImage(data: data)?.size ?? .zero
            return .image(.init(blobName: name, byteCount: data.count, pixelSize: size))
        }
        if !s.fileURLs.isEmpty { return .files(s.fileURLs) }
        if let text = s.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        return nil
    }

    private func hash(for s: PasteboardSnapshot, kind: ClipItem.Kind) -> String {
        switch kind {
        case .text(let t): return Hashing.sha256(Data(t.utf8))
        case .image: return Hashing.sha256(s.imageData ?? Data())
        case .files(let urls): return Hashing.sha256(Data(urls.map(\.path).joined(separator: "\n").utf8))
        }
    }
}

/// Опрос вместо подписки: уведомлений об изменении буфера в macOS нет.
///
/// `@unchecked Sendable`: `lastChangeCount` читает и пишет только обработчик
/// таймера, который сам всегда выполняется на серийной `queue`, — гонки внутри
/// класса нет, но компилятор не может доказать это статически через границу
/// актора при переносе `self` в `DispatchQueue.main.async`.
public final class PasteboardWatcher: @unchecked Sendable {
    private let reader: PasteboardReading
    private var lastChangeCount: Int
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "chelka.pasteboard")

    public var onChange: ((PasteboardSnapshot) -> Void)?

    public init(reader: PasteboardReading = SystemPasteboard()) {
        self.reader = reader
        lastChangeCount = reader.snapshot().changeCount
    }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Config.History.pollInterval,
                   repeating: Config.History.pollInterval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    public func stop() { timer?.cancel(); timer = nil }

    private func poll() {
        let snapshot = reader.snapshot()
        guard snapshot.changeCount != lastChangeCount else { return }
        lastChangeCount = snapshot.changeCount
        DispatchQueue.main.async { [weak self] in self?.onChange?(snapshot) }
    }
}
