import AppKit
import ServiceManagement
import SwiftUI

@MainActor
public final class ChelkaAppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var trigger: TriggerZone?
    private var machine = PanelStateMachine()
    private var geometry = NotchGeometry(rect: .zero, hasPhysicalNotch: false)
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

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        geometry = NotchGeometry.current(screen: screen)

        setUpShelf()

        let panel = NotchPanel(geometry: geometry)
        panel.contentView = defaultContentView()
        panel.orderFrontRegardless()
        self.panel = panel

        trigger = TriggerZone(geometry: geometry,
                              // Наведение идёт через `hovered`, а не прямо в автомат:
                              // раскрытие по наведению можно выключить в настройках,
                              // но уход мыши обрабатывается всегда, иначе панель залипает.
                              onHover: { [weak self] inside in self?.hovered(inside) },
                              onClick: { [weak self] in self?.apply { $0.clicked() } },
                              onDropFiles: { [weak self] urls in self?.acceptDroppedFiles(urls) })

        let statusItem = StatusItemController { [weak self] action in self?.handle(action) }
        self.statusItem = statusItem
        refreshStatusItem()

        setUpClipboard()

        // Хоткей делает ровно то же, что клик по челке и пункт «Показать
        // панель»: раскрывает панель, повторное нажатие складывает её.
        panelHotkey = GlobalHotkey.installed { [weak self] in self?.apply { $0.clicked() } }
    }

    /// Долгоживущие ресурсы гасим сами: регистрация хоткея живёт в системе, а
    /// таймер и наблюдатель за буфером продолжали бы тикать во время выхода.
    public func applicationWillTerminate(_ notification: Notification) {
        panelHotkey?.unregister()
        panelHotkey = nil
        activityTimer?.invalidate()
        activityTimer = nil
        pasteboardWatcher?.stop()
    }

    private func setUpShelf() {
        let coordinator = ShelfCoordinator(index: ShelfIndex(fileURL: AppPaths.shelf))
        shelf = coordinator
        // Чтение полки с проверкой каждого файла на диске — не дело старта
        // на главной очереди: том может быть сетевым. Панель поднимется
        // сразу, полка догрузится через мгновение.
        Task { await coordinator.load() }
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

    /// Стекло с семантическим текстом внутри. Своих цветов не заводим — тема
    /// системная, и переключение светлая/тёмная должно достаться бесплатно.
    /// Раскладка идёт по `NotchLayout.inPanel`, а не занимает всё окно целиком:
    /// текст сидит в теле, под челкой, а полосы слева и справа от неё
    /// зарезервированы под короткие виджеты (время, погода, заряд) — их
    /// подключит отдельная задача, но место под них уже не перекрывает челка.
    private func defaultContentView() -> NSView {
        hosting(GlassPanel {
            NotchPanelContent(geometry: geometry)
        })
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

    /// Содержимое раскрытой панели — сетка истории. Пока буфер не поднят
    /// (первые мгновения после запуска), показываем то же, что и всегда:
    /// сетка без координатора существовать не может.
    private func expandedContentView() -> NSView {
        guard let coordinator = clipboardCoordinator, let blobs, let shelf else {
            return defaultContentView()
        }
        return hosting(GlassPanel {
            HistoryPanelContent(coordinator: coordinator, blobs: blobs, shelf: shelf,
                                geometry: geometry,
                                onClose: { [weak self] in self?.dismissPanelSoon() })
        })
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
            Task { @MainActor in
                self?.activityCenter.tick(now: Date())
                self?.renderActivity()
            }
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
        renderActivity()
    }

    /// Рисует карточку для `activityCenter.queue.current` либо, когда её время
    /// вышло, убирает её и возвращает панель в обычное состояние.
    private func renderActivity() {
        guard let panel, let blobs else { return }
        if let event = activityCenter.queue.current {
            // Карточка тоже принимает файлы: она закрывает челку собой, и без
            // приёмника вокруг неё сброс на челку не сработал бы в те секунды,
            // пока карточка висит.
            panel.contentView = hosting(NotchContinuationFigure {
                ActivityFigureContent(event: event, blobs: blobs, geometry: geometry)
            })
        } else if machine.state == .activity {
            panel.contentView = defaultContentView()
            apply { $0.activityFinished() }
        }
    }

    private func apply(_ transition: (PanelStateMachine) -> PanelStateMachine) {
        let previous = machine.state
        machine = transition(machine)
        // Меню статус-бара и зона-триггер обновляются даже без панели — иначе
        // при отсутствующем окне (например, до первого запуска) аварийный
        // выход и зона над челкой молча замирали бы в устаревшем состоянии.
        // Зона-триггер молчит, пока панель раскрыта, чтобы не воровать у неё мышь.
        trigger?.setInteractive(machine.state != .expanded)
        refreshStatusItem()
        guard let panel else { return }
        // Клавиатуру панель берёт только в раскрытом состоянии — во всех
        // остальных выезжающая карточка не должна перехватывать набор текста
        // у человека, который в этот момент печатает в другом приложении.
        panel.setKeyboardAllowed(NotchPanel.allowsKeyboard(in: machine.state))
        // Содержимое пересобирается только на самом переходе в раскрытое
        // состояние и из него. Пересборка на каждый вызов `apply` обнуляла бы
        // строку поиска, выделение и фокус — а зовут его в том числе на
        // наведение мыши, то есть десятки раз подряд.
        if machine.state == .expanded, previous != .expanded {
            panel.contentView = expandedContentView()
            // Пока панель была закрыта, файлы с полки могли удалить или
            // перенести. Проверка уходит с главной очереди: том бывает сетевым.
            if let shelf { Task { await shelf.pruneMissingFiles() } }
        } else if previous == .expanded, machine.state != .expanded {
            panel.contentView = defaultContentView()
        }
        switch machine.state {
        case .hidden:
            // Панель убирается совсем, а не сжимается в полоску. Сжатая полоска
            // оставалась клавиатурным окном: нажатия пользователя улетали в
            // невидимую щель вместо его приложения.
            panel.orderOut(nil)
        case .peek:
            panel.resize(to: geometry.rect.size, geometry: geometry)
            panel.orderFrontRegardless()
        case .activity:
            // Фигура прижата к верху экрана и продолжает челку. Содержимое при
            // этом лежит ниже челки — за это отвечает раскладка, а не рамка.
            panel.setFrame(NotchLayout.cardFrame(size: activityPanelSize, geometry: geometry),
                           display: true, animate: false)
            panel.orderFrontRegardless()
        case .expanded:
            panel.resize(to: Config.Notch.expandedSize, geometry: geometry)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    private var activityPanelSize: CGSize {
        CGSize(width: max(geometry.rect.width + Config.Activity.cardExtraWidth,
                          Config.Activity.cardMinWidth),
               height: NotchLayout.cardHeight(contentHeight: Config.Activity.cardBodyHeight,
                                              geometry: geometry))
    }

    private func refreshStatusItem() {
        statusItem?.refresh(panel: machine.state,
                            launchesAtLogin: SMAppService.mainApp.status == .enabled)
    }

    private func handle(_ action: StatusMenuAction) {
        switch action {
        case .showPanel:
            apply { _ in PanelStateMachine(state: .expanded) }
        case .openSettings:
            settingsWindow.show()
        case .toggleLaunchAtLogin:
            toggleLaunchAtLogin()
        case .quit:
            NSApp.terminate(nil)
        }
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
        refreshStatusItem()
    }
}

/// Заглушка основного содержимого панели, раскладывающая себя по
/// `NotchLayout.inPanel` вместо того, чтобы занимать окно целиком. Место
/// в теле — под челкой — уже гарантированно не перекрыто ею; полосы слева
/// и справа от челки существуют, но пока пустые: подключить туда время,
/// погоду и заряд — отдельная задача, а не эта.
///
/// `GeometryReader` берёт актуальный размер контейнера на каждый рендер, а
/// не размер на момент создания — так раскладка остаётся верной, когда
/// `GlassPanel` растягивает это же вью при переходе peek → expanded.
private struct NotchPanelContent: View {
    let geometry: NotchGeometry

    var body: some View {
        GeometryReader { proxy in
            let layout = NotchLayout.inPanel(size: proxy.size, geometry: geometry)
            Text("4elka")
                .foregroundStyle(.primary)
                .padding(8)
                .frame(width: layout.body.width, height: layout.body.height)
                .position(x: layout.body.midX, y: proxy.size.height - layout.body.midY)
        }
    }
}

/// Сетка истории и полоса полки под ней, посаженные в тело панели — под челку.
/// Крылья слева и справа от челки им не отдаются: плитка в полосе высотой
/// с челку не читается, а само тело панели раскрытой на `expandedSize`
/// вполне достаточно.
private struct HistoryPanelContent: View {
    let coordinator: ClipboardCoordinator
    let blobs: BlobStore
    let shelf: ShelfCoordinator
    let geometry: NotchGeometry
    let onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = NotchLayout.inPanel(size: proxy.size, geometry: geometry)
            VStack(spacing: 0) {
                HistoryGridView(coordinator: coordinator, blobs: blobs, onClose: onClose)
                ShelfView(coordinator: shelf)
                    .padding(.horizontal, Config.HistoryGrid.padding)
                    .padding(.bottom, Config.HistoryGrid.padding)
            }
            .frame(width: layout.body.width, height: layout.body.height)
            .position(x: layout.body.midX, y: proxy.size.height - layout.body.midY)
        }
    }
}

/// «Фигура», продолжающая физическую челку в стороны и вниз, а не отдельная
/// плашка под ней. Стык с настоящей челкой должен быть незаметен, поэтому
/// фон здесь — единственный явно заданный (не семантический) цвет в проекте:
/// чёрный в любой теме, а не адаптивный `.primary`/`.secondary`. Форсируем
/// тёмную схему для содержимого сверху, чтобы `.foregroundStyle(.primary)` там
/// оставалось читаемым семантическим текстом, а не белым на белом в светлой теме.
/// Скруглены только нижние углы (`notchCornerRadius`) — верхние прижаты к
/// самому верху экрана, где скругление было бы не видно.
private struct NotchContinuationFigure<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .colorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: Config.Notch.notchCornerRadius,
                bottomTrailingRadius: Config.Notch.notchCornerRadius,
                topTrailingRadius: 0))
    }
}

/// Содержимое фигуры-карточки: сама карточка сидит в теле, под челкой — там,
/// где `NotchLayout.inPanel` её не перекрывает. Крылья слева и справа от
/// челки зарезервированы (`cardFrame` гарантирует им место), но пока пустые:
/// подключить туда время, погоду и заряд — отдельная задача, а не эта.
private struct ActivityFigureContent: View {
    let event: ActivityEvent
    let blobs: BlobStore
    let geometry: NotchGeometry

    var body: some View {
        GeometryReader { proxy in
            let layout = NotchLayout.inPanel(size: proxy.size, geometry: geometry)
            ActivityCardView(event: event, blobs: blobs)
                .frame(width: layout.body.width, height: layout.body.height)
                .position(x: layout.body.midX, y: proxy.size.height - layout.body.midY)
        }
    }
}
