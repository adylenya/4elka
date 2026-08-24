import AppKit
import ServiceManagement
import SwiftUI

/// Жизненный цикл приложения и действия меню. Представление состояния окном
/// живёт в `PanelPresenter` и `PanelPresentation`, расчёт рамок — в
/// `PanelFrames`, содержимое панели — в `PanelContentViews`. Раньше всё это
/// было приватным `switch` внутри делегата, и проверить его было нечем.
@MainActor
public final class ChelkaAppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var trigger: TriggerZone?
    private var presenter: PanelPresenter?
    private var machine = PanelStateMachine()
    private var geometry = NotchGeometry.none
    private var screenWatcher: ScreenWatcher?
    // Аварийный выход: единственный способ управлять и выключить приложение,
    // раз у него нет иконки в доке.
    private var statusItem: StatusItemController?
    /// Глобальное сочетание клавиш. Создаётся при старте, снимается при выходе.
    private var panelHotkey: GlobalHotkey?

    // Единая точка отправки карточек на всё приложение: буфер (ниже), плеер
    // (Task 15) и батареи (Task 18) пишут сюда же, а не каждый в свою очередь —
    // иначе приоритет «заряд важнее буфера, буфер важнее трека» не работает.
    private lazy var activityCenter = ActivityCenter(
        panelState: { [weak self] in self?.machine.state ?? .hidden },
        settings: { [weak self] in self?.settingsController.settings ?? .defaults })
    private var blobs: BlobStore?
    private var shelf: ShelfCoordinator?
    private var clipboardCoordinator: ClipboardCoordinator?
    private var pasteboardWatcher: PasteboardWatcher?
    private var activityTimer: Timer?

    /// Единственный владелец настроек на всё приложение. Подсистемы читают
    /// значения отсюда замыканиями, а не копируют их себе при создании: иначе
    /// правка в открытом окне не доходила бы до них до перезапуска.
    private lazy var settingsController: SettingsController = {
        let controller = SettingsController(store: SettingsStore(fileURL: AppPaths.settings))
        controller.onChange = { [weak self] settings in self?.settingsChanged(settings) }
        return controller
    }()

    private lazy var settingsWindow = SettingsWindowController(
        controller: settingsController, actions: settingsActions())

    /// Порядок здесь важен и продиктован находкой ревью: иконка в строке меню
    /// создаётся ПЕРВОЙ и безусловно. Раньше запуск начинался с `guard let
    /// screen = NSScreen.main else { return }`, и вход с ещё не проснувшимся
    /// дисплеем оставлял живой процесс без единого элемента интерфейса —
    /// выключить его можно было только через мониторинг системы.
    public func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = StatusItemController { [weak self] action in self?.handle(action) }
        self.statusItem = statusItem

        setUpShelf()
        setUpClipboard()
        setUpWindows()

        // Пересчёт геометрии на смену экрана, разрешения и масштаба. Без него
        // панель и невидимая зона оставались на старых координатах: наведение
        // не работало, а окно, съедающее клики, стояло где-то в строке меню.
        screenWatcher = ScreenWatcher { [weak self] in self?.screenParametersChanged() }

        // Хоткей делает ровно то же, что клик по челке и пункт «Показать
        // панель»: раскрывает панель, повторное нажатие складывает её.
        panelHotkey = GlobalHotkey.installed { [weak self] in self?.apply { $0.clicked() } }

        // Состояние применяется до первого показа окна. Раньше панель
        // поднималась на передний план при скрытом состоянии, и на машине без
        // выреза в центре строки меню висела видимая плашка, не исчезавшая до
        // первой пары «вошёл-вышел» мышью.
        refresh()
    }

    /// Долгоживущие ресурсы гасим сами: регистрация хоткея живёт в системе, а
    /// таймер, наблюдатель за буфером и наблюдатель за экранами продолжали бы
    /// работать во время выхода.
    public func applicationWillTerminate(_ notification: Notification) {
        panelHotkey?.unregister()
        panelHotkey = nil
        activityTimer?.invalidate()
        activityTimer = nil
        pasteboardWatcher?.stop()
        screenWatcher?.stop()
        screenWatcher = nil
    }

    // MARK: - Окна

    private func setUpWindows() {
        geometry = ScreenChoice.geometry()

        let panel = NotchPanel(geometry: geometry)
        self.panel = panel

        let trigger = TriggerZone(geometry: geometry,
                                  // Наведение идёт через `hovered`, а не прямо в автомат:
                                  // раскрытие по наведению можно выключить в настройках,
                                  // но уход мыши обрабатывается всегда, иначе панель залипает.
                                  onHover: { [weak self] inside in self?.hovered(inside) },
                                  onClick: { [weak self] in self?.apply { $0.clicked() } },
                                  onDropFiles: { [weak self] urls in self?.acceptDroppedFiles(urls) })
        self.trigger = trigger

        presenter = PanelPresenter(panel: panel, trigger: trigger,
                                   content: { [weak self] content in
                                       self?.contentView(for: content)
                                   })
    }

    /// Экран сменился, отключился или сменил разрешение. Геометрия
    /// пересчитывается, оба окна переставляются, текущее состояние применяется
    /// заново — этим занимается `refresh`.
    private func screenParametersChanged() {
        geometry = ScreenChoice.geometry()
        // Содержимое считает своё место от геометрии, поэтому при её смене оно
        // обязано пересобраться, даже если состояние то же.
        presenter?.invalidateContent()
        refresh()
    }

    // MARK: - Состояние

    private func apply(_ transition: (PanelStateMachine) -> PanelStateMachine) {
        let previous = machine.state
        machine = transition(machine)
        // Уже летящее событие гасим при выходе из состояния «карточка». Иначе
        // оно продолжало тикать под раскрытой панелью, и очередь оставалась
        // непустой неизвестно сколько.
        if previous == .activity, machine.state != .activity {
            activityCenter.clear()
        }
        if machine.state == .expanded, previous != .expanded {
            // Пока панель была закрыта, файлы с полки могли удалить или
            // перенести. Проверка уходит с главной очереди: том бывает сетевым.
            if let shelf { Task { await shelf.pruneMissingFiles() } }
        }
        refresh()
    }

    /// Единственная точка, из которой окна узнают о состоянии. Всё решение —
    /// чистое значение `PanelPresentation`, поэтому проверяется тестом целиком.
    private func refresh() {
        presenter?.apply(PanelPresentation.make(state: machine.state,
                                                event: activityCenter.queue.current,
                                                geometry: geometry))
        statusItem?.refresh(panel: machine.state,
                            launchesAtLogin: SMAppService.mainApp.status == .enabled)
    }

    /// Наведение на челку раскрывает панель только если это разрешено
    /// настройкой. Выключено — панель открывается кликом или комбинацией
    /// клавиш, а мышь, проходящая мимо, ничего не дёргает.
    ///
    /// Уход мыши обрабатывается всегда, при любой настройке: иначе панель,
    /// уже показанная по наведению, осталась бы висеть навсегда, если тумблер
    /// выключить в этот самый момент.
    private func hovered(_ inside: Bool) {
        guard settingsController.settings.opensOnHover || !inside else { return }
        apply { $0.hovering(inside) }
    }

    /// Закрытие приходит из обработчика внутри самой сетки, а гашение панели
    /// сносит хостинг-вью этой сетки. Делать это посреди её же события —
    /// напрашиваться на падение, поэтому переход откладывается на следующий
    /// проход цикла событий.
    private func dismissPanelSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.apply { $0.dismissed() }
        }
    }

    // MARK: - Содержимое панели

    /// Сборка содержимого по его виду. Зовётся только когда вид действительно
    /// поменялся — за это отвечает `PanelPresenter`.
    private func contentView(for content: PanelContent) -> NSView? {
        switch content.kind {
        case .hint:
            return hosting(PeekHintView(geometry: geometry))
        case .activity:
            guard let event = activityCenter.queue.current else { return nil }
            return hosting(ActivityFigureContent(event: event,
                                                 image: thumbnail(for: event),
                                                 geometry: geometry))
        case .history:
            guard let coordinator = clipboardCoordinator, let blobs, let shelf else { return nil }
            return hosting(NotchToppedPanel(geometry: geometry) {
                HistoryPanelContent(coordinator: coordinator, blobs: blobs, shelf: shelf,
                                    onClose: { [weak self] in self?.dismissPanelSoon() })
            })
        }
    }

    /// Картинка карточки читается здесь, один раз на событие, а не внутри
    /// отрисовки: снимок бывает под сорок мегабайт, и чтение в отрисовке
    /// повторялось на каждый тик таймера.
    private func thumbnail(for event: ActivityEvent) -> NSImage? {
        guard let blobs, let name = event.imageBlobName else { return nil }
        return NSImage(contentsOf: blobs.url(for: name))
    }

    /// Любое содержимое панели живёт внутри приёмника файлов, а не рядом с ним:
    /// AppKit ищет получателя сброса, поднимаясь от вью под курсором к её
    /// родителям, поэтому «принимать файлы в любом месте панели» умеет только
    /// родитель. Слой поверх содержимого не годится вовсе — он съел бы нажатия
    /// у плиток истории и убил бы перетаскивание наружу.
    private func hosting<Content: View>(_ content: Content) -> NSView {
        let dropper = FileDropView()
        dropper.onDrop = { [weak self] urls in self?.acceptDroppedFiles(urls) }
        dropper.embed(NSHostingView(rootView: content))
        return dropper
    }

    /// Файлы, брошенные на челку или на раскрытую панель.
    ///
    /// Раскрытие панели отложено на следующий проход цикла событий: перестраивать
    /// вью прямо внутри обработки сброса — напрашиваться на падение, ведь жест
    /// в этот момент ещё завершается. Заодно панель не забирает клавиатуру
    /// посреди чужого перетаскивания.
    private func acceptDroppedFiles(_ urls: [URL]) {
        guard let shelf, !urls.isEmpty else { return }
        shelf.add(urls)
        DispatchQueue.main.async { [weak self] in
            self?.apply { _ in PanelStateMachine(state: .expanded) }
        }
    }

    // MARK: - Подсистемы

    private func setUpShelf() {
        let coordinator = ShelfCoordinator(index: ShelfIndex(fileURL: AppPaths.shelf))
        shelf = coordinator
        // Чтение полки с проверкой каждого файла на диске — не дело старта
        // на главной очереди: том может быть сетевым. Панель поднимется
        // сразу, полка догрузится через мгновение.
        Task { await coordinator.load() }
    }

    private func setUpClipboard() {
        let blobs = BlobStore(root: AppPaths.blobs)
        self.blobs = blobs
        try? FileManager.default.createDirectory(at: AppPaths.blobs, withIntermediateDirectories: true)

        let index = HistoryIndex(fileURL: AppPaths.index, blobs: blobs)
        let capture = ClipboardCapture(rules: { [weak self] in
                                           self?.settingsController.settings.ignoreRules
                                               ?? Settings.defaults.ignoreRules
                                       },
                                       blobs: blobs,
                                       quotas: { [weak self] in
                                           self?.settingsController.settings.historyQuotas ?? .default
                                       })
        let coordinator = ClipboardCoordinator(capture: capture, index: index, blobs: blobs,
                                               activity: activityCenter)
        clipboardCoordinator = coordinator

        let watcher = PasteboardWatcher()
        watcher.onChange = { [weak self, weak coordinator] snapshot in
            coordinator?.handle(snapshot, now: Date())
            self?.presentActivityIfNeeded()
        }
        watcher.start()
        pasteboardWatcher = watcher
        // Клик по элементу истории пишет в буфер сам. Без этой связки
        // наблюдатель увидит нашу же запись как чужое копирование: элемент
        // вернётся в историю, а карточка «скопировано» выедет ровно в тот
        // момент, когда панель закрывается.
        coordinator.reportSelfWrite = { [weak watcher] count in
            watcher?.ignoreSelfWrite(changeCount: count)
        }

        activityTimer = Timer.scheduledTimer(withTimeInterval: Config.Activity.tickInterval,
                                             repeats: true) { [weak self] _ in
            Task { @MainActor in self?.activityTick() }
        }
    }

    /// Единая точка входа для внешних поставщиков карточек (плеер — Task 15,
    /// батареи — Task 18): кладёт событие в общую очередь и, если оно
    /// действительно стало видимым (не проиграло по приоритету), показывает панель.
    func submitActivity(_ event: ActivityEvent) {
        activityCenter.submit(event, now: Date())
        presentActivityIfNeeded()
    }

    private func presentActivityIfNeeded() {
        guard activityCenter.queue.current != nil else { return }
        apply { $0.showingActivity() }
    }

    /// Время карточки вышло — возвращаем панель в обычное состояние. Отрисовкой
    /// тик не занимается: содержимое пересобирается только когда меняется
    /// событие, и это решает `PanelPresenter`.
    private func activityTick() {
        activityCenter.tick(now: Date())
        guard activityCenter.queue.current == nil, machine.state == .activity else { return }
        apply { $0.activityFinished() }
    }

    // MARK: - Меню и настройки

    private func handle(_ action: StatusMenuAction) {
        switch action {
        case .showPanel:
            apply { _ in PanelStateMachine(state: .expanded) }
        case .hidePanel:
            apply { $0.dismissed() }
        case .openSettings:
            settingsWindow.show()
        case .toggleLaunchAtLogin:
            toggleLaunchAtLogin()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// Что нужно применить сразу, а не при следующем событии. Уменьшенная
    /// квота истории — именно такой случай: ждать очередного копирования
    /// означало бы «сколько хранить» вступает в силу неизвестно когда.
    private func settingsChanged(_ settings: Settings) {
        clipboardCoordinator?.applyQuotas(settings.historyQuotas)
    }

    /// Действия для окна настроек: сама вьюха ни истории, ни системной службы
    /// не знает и знать не должна.
    private func settingsActions() -> SettingsActions {
        SettingsActions(
            clearHistory: { [weak self] in self?.clipboardCoordinator?.clearHistory() },
            isLaunchAtLoginEnabled: { SMAppService.mainApp.status == .enabled },
            toggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            revealDataFolder: {
                // Каталог мог ещё не появиться: до первого копирования писать
                // в него нечего, а Finder на несуществующем пути ничего не
                // покажет и промолчит.
                try? FileManager.default.createDirectory(at: AppPaths.support,
                                                        withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([AppPaths.support])
            })
    }

    private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            // Из дерева сборки регистрация не сработает, потому что
            // приложение не лежит в /Applications — это нормально.
            // Ошибку пишем в лог, а не глотаем и не выдаём за успех.
            NSLog("4elka: не удалось изменить автозапуск: %@", String(describing: error))
        }
        refresh()
    }
}
