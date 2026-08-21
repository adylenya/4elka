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

    // Единая точка отправки карточек на всё приложение: буфер (ниже), плеер
    // (Task 15) и батареи (Task 18) пишут сюда же, а не каждый в свою очередь —
    // иначе приоритет «заряд важнее буфера, буфер важнее трека» не работает.
    private lazy var activityCenter = ActivityCenter(panelState: { [weak self] in
        self?.machine.state ?? .hidden
    })
    private var blobs: BlobStore?
    private var clipboardCoordinator: ClipboardCoordinator?
    private var pasteboardWatcher: PasteboardWatcher?
    private var activityTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        geometry = NotchGeometry.current(screen: screen)

        let panel = NotchPanel(geometry: geometry)
        panel.contentView = defaultContentView()
        panel.orderFrontRegardless()
        self.panel = panel

        trigger = TriggerZone(geometry: geometry,
                              onHover: { [weak self] inside in self?.apply { $0.hovering(inside) } },
                              onClick: { [weak self] in self?.apply { $0.clicked() } })

        let statusItem = StatusItemController { [weak self] action in self?.handle(action) }
        self.statusItem = statusItem
        refreshStatusItem()

        setUpClipboard()
    }

    /// Стекло с семантическим текстом внутри. Своих цветов не заводим — тема
    /// системная, и переключение светлая/тёмная должно достаться бесплатно.
    private func defaultContentView() -> NSView {
        NSHostingView(rootView: GlassPanel {
            Text("4elka").foregroundStyle(.primary).padding(8)
        })
    }

    private func setUpClipboard() {
        let blobs = BlobStore(root: AppPaths.blobs)
        self.blobs = blobs
        try? FileManager.default.createDirectory(at: AppPaths.blobs, withIntermediateDirectories: true)

        let index = HistoryIndex(fileURL: AppPaths.index, blobs: blobs)
        let capture = ClipboardCapture(rules: IgnoreRules(ownBundleID: Config.ownBundleID), blobs: blobs)
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
            panel.contentView = NSHostingView(rootView: GlassPanel {
                ActivityCardView(event: event, blobs: blobs)
            })
        } else if machine.state == .activity {
            panel.contentView = defaultContentView()
            apply { $0.activityFinished() }
        }
    }

    private func apply(_ transition: (PanelStateMachine) -> PanelStateMachine) {
        machine = transition(machine)
        guard let panel else { return }
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
            // Шире самой челки — иначе карточке негде показать текст и миниатюру.
            panel.resize(to: activityPanelSize, geometry: geometry)
            panel.orderFrontRegardless()
        case .expanded:
            panel.resize(to: Config.Notch.expandedSize, geometry: geometry)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
        // Зона-триггер молчит, пока панель раскрыта, чтобы не воровать у неё мышь.
        trigger?.setInteractive(machine.state != .expanded)
        refreshStatusItem()
    }

    private var activityPanelSize: CGSize {
        CGSize(width: max(geometry.rect.width + Config.Activity.cardExtraWidth,
                          Config.Activity.cardMinWidth),
              height: Config.Activity.cardHeight)
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
            // Заглушка: настоящее окно настроек — Task 26.
            let alert = NSAlert()
            alert.messageText = "Настройки"
            alert.informativeText = "Здесь будет окно настроек."
            alert.runModal()
        case .toggleLaunchAtLogin:
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
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
