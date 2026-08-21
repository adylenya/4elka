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
    /// Файлы картинок, которых в истории уже нет, но удалять их пока рано:
    /// индекс на диске всё ещё может на них ссылаться. Список разбирается сразу
    /// после успешной записи индекса — см. `persist()`.
    private var blobsToDelete: [String] = []

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
        blobsToDelete += result.evictedBlobNames
        activity.submit(Self.activityEvent(for: item), now: now)
        scheduleSave()
    }

    /// Пересчёт квот по новым настройкам. Ждать следующего копирования нельзя:
    /// уменьшенное «сколько хранить» вступало бы в силу неизвестно когда.
    /// Вытесненные блобы удаляются здесь же, иначе файлы остались бы сиротами.
    public func applyQuotas(_ quotas: HistoryQuotas) {
        let before = history
        let next = history.applyingQuotas(quotas)
        guard next != before else { return }
        history = next
        // Имена вытесненных файлов складываем в очередь на удаление, а не
        // удаляем сразу: файл нельзя убирать, пока индекс, который на него
        // ссылается, не лёг на диск. Иначе после выхода в неудачный момент
        // история теряет запись целиком.
        blobsToDelete += next.evictedBlobNames(comparedTo: before)
        // Уменьшение квоты — воля человека из настроек, а не поток копирований:
        // пишем сразу.
        saveNow()
    }

    /// Полная очистка по кнопке из настроек. При первом запуске приложение
    /// подхватывает то, что уже лежало в буфере, и человек должен уметь стереть
    /// это, не лазая в терминал.
    ///
    /// Закреплённое тоже уходит: человек нажал «Очистить историю» и подтвердил,
    /// а история с остатками — не пустая история. Файлы сносятся все, включая
    /// потерявшие свою запись: осиротевших файлов после очистки быть не должно.
    /// Индекс пишется сразу, а не с задержкой — стёртое не должно вернуться,
    /// если приложение выключат в следующую секунду.
    public func clearHistory() {
        history = HistoryStore()
        // Очередь на удаление больше не нужна: сносим каталог целиком, и в нём
        // всё равно не останется ни одного файла — включая те, что ждали записи.
        blobsToDelete = []
        // Индекс пишем ПЕРВЫМ: если приложение выключат между двумя строками,
        // пустой индекс с уже стёртыми файлами безопасен, а полный индекс без
        // файлов — это потерянные записи, которые загрузка молча выбросит.
        saveNow()
        blobs.removeAll()
    }

    // Закрепление — воля человека, а не поток копирований: пишем сразу, без
    // задержки. Иначе закрепление не выживало выхода из приложения.
    public func pin(_ id: UUID) { history = history.pinning(id); saveNow() }
    public func unpin(_ id: UUID) { history = history.unpinning(id); saveNow() }

    public func remove(_ id: UUID) { remove([id]) }

    /// Удаление всего выделенного одной операцией. Не циклом снаружи: блобы
    /// сравниваются с состоянием ДО всей группы, иначе картинка, вытесненная
    /// квотой в середине цикла, осталась бы файлом на диске навсегда.
    public func remove(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let before = history
        history = ids.reduce(history) { $0.removing($1) }
        blobsToDelete += history.evictedBlobNames(comparedTo: before)
        saveNow()
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
        saveNow()
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

    /// Убрать файлы картинок, которых больше никто не держит. Зовётся при старте,
    /// сразу после загрузки истории: элементы без файлов история отбрасывает сама,
    /// а файлы без элементов убрать больше нечем — они оставались от каждого
    /// падения между записью файла и записью индекса.
    ///
    /// Файлы, ждущие удаления после записи индекса, тоже считаются удерживаемыми:
    /// индекс на диске всё ещё может на них ссылаться, и снести их раньше записи
    /// значило бы потерять запись целиком.
    public func collectOrphanBlobs(now: Date = Date()) {
        let held = Set(history.items.compactMap(\.blobName)).union(blobsToDelete)
        let orphans = BlobGarbage.collectable(files: blobs.files(), referenced: held, now: now)
        guard !orphans.isEmpty else { return }
        NSLog("4elka: убрано осиротевших файлов картинок: %d", orphans.count)
        blobs.delete(orphans)
    }

    /// Сбросить историю на диск немедленно. Зовётся при выходе из приложения:
    /// всё, что попало в окно задержки и живёт только в памяти, иначе пропало бы.
    public func flush() { saveNow() }

    /// Немедленная запись: отложенная запись отменяется, чтобы не сработать
    /// вторым разом впустую. Так пишется всё, что выражает волю человека —
    /// удаление и закрепление: задержка нужна только потоку копирований,
    /// а не решениям, которые человек принял руками.
    private func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        persist()
    }

    /// Индекс пишется с задержкой: при быстрой серии копирований файл не должен
    /// перезаписываться пять раз в секунду. Первое изменение после затишья
    /// сохраняется сразу — иначе один-единственный клип, скопированный прямо
    /// перед выходом из приложения, мог бы не долежать до диска. Всё, что
    /// прилетает внутри окна `indexWriteDebounce` после этого, схлопывается
    /// в одну финальную запись по истечении окна — а если приложение закроется
    /// раньше, эту запись выполнит `flush()`.
    private func scheduleSave() {
        guard saveWork == nil else { return }
        persist()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveWork = nil
            self.persist()
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.History.indexWriteDebounce,
                                      execute: work)
    }

    /// Пишет индекс и только после успешной записи убирает файлы картинок,
    /// на которые в нём больше нет ссылок.
    ///
    /// Порядок здесь важнее удобства. Удалив файл раньше записи, мы оставляли бы
    /// на диске индекс со ссылкой на исчезнувший файл — а такие элементы `load()`
    /// отбрасывает, то есть закреплённая картинка пропадала бы целиком. Если
    /// запись не удалась, файлы остаются на месте и ждут следующей попытки:
    /// лишний файл на диске несравнимо дешевле потерянной записи.
    ///
    /// Отказ диска не глотаем: без записи в лог сбой выглядел бы как успех,
    /// а история молча оставалась бы только в памяти.
    private func persist() {
        do {
            try index.save(history)
        } catch {
            NSLog("4elka: индекс истории не записан, изменения остались только в памяти: %@",
                  String(describing: error))
            return
        }
        let names = blobsToDelete
        blobsToDelete = []
        blobs.delete(names)
    }
}
