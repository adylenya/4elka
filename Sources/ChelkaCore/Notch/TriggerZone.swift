import AppKit

/// Прозрачное окно ровно по челке, которое ловит наведение, клик и брошенные
/// на челку файлы. Без этого окна навести на схлопнутую челку и поймать
/// hover/клик/сброс было бы нечем.
///
/// ⚠️ Уровень окна на единицу выше уровня панели, и это главное в этом типе.
/// Панель поднимается на передний план на каждом переходе, а зона поднималась
/// один раз при запуске: на одном уровне панель оказывалась выше и в состоянии
/// наведения накрывала зону целиком, оставаясь интерактивной. Наведение всегда
/// раньше клика, поэтому нажатие попадало в панель, у которой нет ни одного
/// обработчика мыши, и съедалось — раскрытие было недостижимо, то есть главный
/// жест приложения не работал никогда.
@MainActor
public final class TriggerZone: TriggerSurface {
    private let window: NSPanel
    private let view: TrackingView
    private let dropper: FileDropView

    /// Зона принимает мышь всегда, пока есть экран, — в том числе при раскрытой
    /// панели: иначе из раскрытого состояния нельзя выйти кликом вовсе. Верхняя
    /// полоса раскрытой панели — чёрная фигура, продолжающая челку; ни плиток
    /// истории, ни источников перетаскивания там нет, и воровать у панели
    /// нечего. Отключается зона только когда экрана нет: невидимое окно,
    /// съедающее нажатия, не должно висеть в строке меню.
    ///
    /// Приём файлов держится на том же: окно, пропускающее мышь, прозрачно и
    /// для перетаскивания, поэтому в любой момент файлы принимает ровно одна
    /// поверхность — зона над челкой либо сама панель (её содержимое целиком
    /// лежит внутри такого же приёмника).
    public func setInteractive(_ enabled: Bool) {
        window.ignoresMouseEvents = !enabled
    }

    /// Переезд на новое место челки: сменился экран, разрешение или масштаб.
    /// Без этого зона остаётся на старых координатах — наведение не работает, а
    /// невидимое окно, съедающее нажатия, стоит где-то в строке меню.
    public func move(to rect: CGRect) {
        guard !rect.isEmpty else {
            // Экрана нет — зоне негде стоять, и висеть в углу она не должна.
            window.orderOut(nil)
            return
        }
        window.setFrame(rect, display: false)
        // Следящая вью растянута по приёмнику констрейнтами, поэтому сначала
        // раскладка, и только потом пересчёт области отслеживания: иначе она
        // считалась бы по прежним границам и наведение срабатывало бы на
        // старом месте.
        dropper.layoutSubtreeIfNeeded()
        view.updateTrackingAreas()
        window.orderFrontRegardless()
    }

    public init(geometry: NotchGeometry,
                onHover: @escaping (Bool) -> Void,
                onClick: @escaping () -> Void,
                onDropFiles: @escaping ([URL]) -> Void = { _ in }) {
        window = NSPanel(contentRect: geometry.rect,
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.level = NSWindow.Level(
            rawValue: NSWindow.Level.statusBar.rawValue + Config.Notch.triggerLevelOffset)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        view = TrackingView(frame: NSRect(origin: .zero, size: geometry.rect.size))
        view.onHover = onHover
        view.onClick = onClick
        // Приёмник файлов — родитель следящей вью, а не слой поверх неё: AppKit
        // ищет получателя сброса, поднимаясь от вью под курсором по родителям,
        // а слой сверху съел бы наведение и клик по челке.
        dropper = FileDropView(frame: NSRect(origin: .zero, size: geometry.rect.size))
        dropper.onDrop = onDropFiles
        dropper.embed(view)
        window.contentView = dropper
        window.orderFrontRegardless()
    }

    @MainActor
    private final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        var onClick: (() -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.mouseEnteredAndExited, .activeAlways],
                                           owner: self, userInfo: nil))
        }

        /// Без этого первое нажатие в неактивном окне AppKit тратит на
        /// «поднять окно вперёд» и вью его не видит вовсе. Приложение живёт
        /// политикой `.accessory` и не активируется никогда, поэтому «первым»
        /// для этого окна оказывается КАЖДОЕ нажатие: без разрешения клик по
        /// челке не доходил бы до обработчика ни разу.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }

        /// Было ли нажатие внутри зоны. Клик — это пара «нажал и отпустил здесь»,
        /// а не одинокое отпускание: иначе перетаскивание, начатое в чужом
        /// окне и завершённое над челкой, читалось бы как клик.
        private var pressedInside = false

        /// Нажатие только запоминаем и передаём дальше по цепочке ответчиков,
        /// а панель переключаем по ОТПУСКАНИЮ. Переключение по нажатию не
        /// давало начаться перетаскиванию из этой полосы: жест умирал в первом
        /// же событии.
        override func mouseDown(with event: NSEvent) {
            pressedInside = bounds.contains(convert(event.locationInWindow, from: nil))
            super.mouseDown(with: event)
        }

        /// Отпускание за пределами зоны — это конец перетаскивания или промах,
        /// а не клик по челке.
        override func mouseUp(with event: NSEvent) {
            let wasPressed = pressedInside
            pressedInside = false
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            guard wasPressed, inside else {
                super.mouseUp(with: event)
                return
            }
            onClick?()
        }
    }
}
