import Foundation

@MainActor
public final class ClipboardCoordinator: ObservableObject {
    @Published public private(set) var history: HistoryStore

    private let capture: ClipboardCapture
    private let index: HistoryIndex
    private let blobs: BlobStore
    private let activity: ActivityCenter
    private var saveWork: DispatchWorkItem?

    public init(capture: ClipboardCapture, index: HistoryIndex, blobs: BlobStore,
                activity: ActivityCenter) {
        self.capture = capture
        self.index = index
        self.blobs = blobs
        self.activity = activity
        history = index.load()
    }

    public func handle(_ snapshot: PasteboardSnapshot, now: Date) {
        let result = capture.capture(snapshot, into: history, now: now)
        guard let item = result.inserted else { return }
        history = result.store
        blobs.delete(result.evictedBlobNames)
        activity.submit(Self.activityEvent(for: item), now: now)
        scheduleSave()
    }

    public func pin(_ id: UUID) { history = history.pinning(id); scheduleSave() }
    public func unpin(_ id: UUID) { history = history.unpinning(id); scheduleSave() }

    public func remove(_ id: UUID) {
        let before = history
        history = history.removing(id)
        blobs.delete(history.evictedBlobNames(comparedTo: before))
        scheduleSave()
    }

    public nonisolated static func activityEvent(for item: ClipItem) -> ActivityEvent {
        switch item.kind {
        case .text(let t):
            let line = t.split(separator: "\n", omittingEmptySubsequences: false)
                .first.map(String.init) ?? t
            return ActivityEvent(kind: .clipboard, title: line, subtitle: "скопировано")
        case .image(let ref):
            return ActivityEvent(kind: .clipboard, title: "Картинка",
                                 subtitle: "\(Int(ref.pixelSize.width)) × \(Int(ref.pixelSize.height))",
                                 imageBlobName: ref.blobName)
        case .files(let urls):
            return ActivityEvent(kind: .clipboard,
                                 title: urls.map(\.lastPathComponent).joined(separator: ", "),
                                 subtitle: "файлов: \(urls.count)")
        }
    }

    /// Индекс пишется с задержкой: при быстрой серии копирований файл не должен
    /// перезаписываться пять раз в секунду. Первое изменение после затишья
    /// сохраняется сразу — иначе один-единственный клип, скопированный прямо
    /// перед выходом из приложения, мог бы не долежать до диска. Всё, что
    /// прилетает внутри окна `indexWriteDebounce` после этого, схлопывается
    /// в одну финальную запись по истечении окна.
    private func scheduleSave() {
        guard saveWork == nil else { return }
        try? index.save(history)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveWork = nil
            try? self.index.save(self.history)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.History.indexWriteDebounce,
                                      execute: work)
    }
}
