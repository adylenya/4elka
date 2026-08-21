import AppKit
import Foundation

@MainActor
public final class ClipboardCoordinator: ObservableObject {
    @Published public private(set) var history: HistoryStore

    private let capture: ClipboardCapture
    private let index: HistoryIndex
    private let blobs: BlobStore
    private let activity: ActivityCenter
    private let dragRoot: URL
    private var saveWork: DispatchWorkItem?

    /// Кому сообщить, что очередная запись в буфер — наша собственная.
    /// Без этого наблюдатель увидит её как чужое копирование, вернёт элемент
    /// в историю и поднимет карточку «скопировано» ровно в тот момент, когда
    /// панель закрывается. Ставит `ChelkaAppDelegate`, замыкая на наблюдателя.
    public var reportSelfWrite: ((Int) -> Void)?

    /// `dragRoot` вынесен в параметр только ради тестов: они не должны сыпать
    /// файлы жеста в общий `AppPaths.dragTemp`, где их увидит и уборщик, и
    /// соседний тест. Приложение пользуется значением по умолчанию.
    public init(capture: ClipboardCapture, index: HistoryIndex, blobs: BlobStore,
                activity: ActivityCenter, dragRoot: URL = AppPaths.dragTemp) {
        self.capture = capture
        self.index = index
        self.blobs = blobs
        self.activity = activity
        self.dragRoot = dragRoot
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

    public func remove(_ id: UUID) { remove([id]) }

    /// Удаление всего выделенного одной операцией. Не циклом снаружи: блобы
    /// сравниваются с состоянием ДО всей группы, иначе картинка, вытесненная
    /// квотой в середине цикла, осталась бы файлом на диске навсегда.
    public func remove(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let before = history
        history = ids.reduce(history) { $0.removing($1) }
        blobs.delete(history.evictedBlobNames(comparedTo: before))
        scheduleSave()
    }

    /// `⌘P` по выделению. Если хоть один элемент не закреплён — закрепляем всё
    /// выделение; иначе снимаем со всего. Переключать каждый по-своему нельзя:
    /// одна клавиша давала бы внутри выделения разнобой, который потом нечем
    /// починить одним нажатием.
    public func togglePin(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let selected = ids.compactMap { id in history.items.first { $0.id == id } }
        let shouldPin = selected.contains { !$0.isPinned }
        history = ids.reduce(history) { shouldPin ? $0.pinning($1) : $0.unpinning($1) }
        scheduleSave()
    }

    /// Обычный клик по плитке: содержимое уходит в системный буфер, дальше
    /// человек вставляет его сам своим `cmd+V` — синтетических нажатий мы
    /// не посылаем и разрешения на управление компьютером не просим.
    public func copyToPasteboard(_ id: UUID) {
        guard let item = history.items.first(where: { $0.id == id }) else { return }
        reportSelfWrite?(Self.write(item, to: .general, blobs: blobs))
    }

    /// Запись в буфер вынесена в статический метод с внешним буфером: тест
    /// проверяет её на своём именованном буфере, не касаясь системного.
    /// Возвращает номер записи, по которому наблюдатель узнаёт своё.
    @discardableResult
    nonisolated static func write(_ item: ClipItem, to pasteboard: NSPasteboard,
                                  blobs: BlobStore) -> Int {
        let changeCount = pasteboard.clearContents()
        switch item.kind {
        case .text(let s):
            pasteboard.setString(s, forType: .string)
        case .image(let ref):
            let url = blobs.url(for: ref.blobName)
            // Блоб мог исчезнуть с диска. Буфер уже очищен, и это правильно:
            // подсунуть вместо картинки прошлое содержимое буфера хуже, чем
            // отдать пустой буфер, — человек хотя бы увидит, что вставлять нечего.
            guard let data = try? Data(contentsOf: url) else {
                NSLog("4elka: блоб %@ пропал, в буфер нечего положить", ref.blobName)
                break
            }
            pasteboard.setData(data, forType: Self.pasteboardType(forExtension: url.pathExtension))
        case .files(let urls):
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        }
        return changeCount
    }

    private nonisolated static func pasteboardType(forExtension ext: String) -> NSPasteboard.PasteboardType {
        ext.lowercased() == "png" ? .png : .tiff
    }

    /// Готовит выделенное к перетаскиванию наружу.
    ///
    /// Лениво: файлы делаются в момент начала жеста, а не заранее на всю
    /// историю — иначе каталог заполнялся бы копиями всего, что человек
    /// когда-либо копировал.
    ///
    /// Ошибка ловится по каждому элементу отдельно. Пропавший с диска блоб
    /// выбрасывает из жеста один элемент, а не ломает перетаскивание целиком.
    public func materializeForDrag(_ ids: [UUID]) -> [URL] {
        DragTempCleaner(root: dragRoot).sweep(now: Date())
        let materializer = DragMaterializer(root: dragRoot)
        let selected = ids.compactMap { id in history.items.first { $0.id == id } }
        return selected.compactMap { Self.materialize($0, with: materializer, blobs: blobs) }
    }

    private nonisolated static func materialize(_ item: ClipItem, with materializer: DragMaterializer,
                                                blobs: BlobStore) -> URL? {
        do {
            switch item.kind {
            case .text(let s):
                return try materializer.materialize(text: s, displayName: dragName(for: item))
            case .image(let ref):
                return try materializer.materialize(blob: blobs.url(for: ref.blobName),
                                                    displayName: dragName(for: item))
            case .files(let urls):
                // Файлы уже лежат на диске под своими именами — копия была бы
                // и лишней работой, и вторым файлом там, куда его перетащат.
                return urls.first
            }
        } catch {
            NSLog("4elka: элемент выброшен из перетаскивания: %@", String(describing: error))
            return nil
        }
    }

    /// Имя, под которым элемент упадёт в Finder. `nonisolated`, потому что это
    /// чистая функция от элемента: тест обязан звать её без главного актора.
    nonisolated static func dragName(for item: ClipItem) -> String {
        switch item.kind {
        case .image: return "Снимок \(timestamp(item.createdAt))"
        case .text(let s):
            let line = s.split(separator: "\n").first.map(String.init) ?? "фрагмент"
            return String(line.prefix(Config.Drag.nameMaxLength))
        case .files(let urls): return urls.first?.lastPathComponent ?? "файл"
        }
    }

    /// Формат фиксированный, поэтому и локаль фиксированная: `en_US_POSIX`
    /// не даст чужому календарю в системных настройках превратить год в 1447.
    private nonisolated static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: Config.timezone)
        formatter.dateFormat = Config.Drag.nameDateFormat
        return formatter.string(from: date)
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
