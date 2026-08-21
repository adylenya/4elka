import AppKit

/// Прозрачное окно ровно по челке, которое ловит наведение, клик и брошенные
/// на челку файлы, когда панель скрыта. Без этого окна навести на схлопнутую
/// челку и поймать hover/клик/сброс было бы нечем.
@MainActor
public final class TriggerZone {
    private let window: NSPanel
    private let onHover: (Bool) -> Void
    private let onClick: () -> Void

    /// Пока панель раскрыта, зона обязана перестать принимать мышь. Иначе она
    /// лежит поверх раскрытой панели и съедает нажатия в верхней её части —
    /// в том числе начало перетаскивания, то есть главный жест приложения.
    ///
    /// Приём файлов от этого не страдает, а ровно так и работает: окно,
    /// пропускающее мышь, прозрачно и для перетаскивания, поэтому в любой
    /// момент файлы принимает ровно одна поверхность — зона над челкой, пока
    /// панель схлопнута, и сама панель, когда она раскрыта (её содержимое
    /// целиком лежит внутри такого же приёмника).
    public func setInteractive(_ enabled: Bool) {
        window.ignoresMouseEvents = !enabled
    }

    public init(geometry: NotchGeometry,
                onHover: @escaping (Bool) -> Void,
                onClick: @escaping () -> Void,
                onDropFiles: @escaping ([URL]) -> Void = { _ in }) {
        self.onHover = onHover
        self.onClick = onClick
        window = NSPanel(contentRect: geometry.rect,
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let view = TrackingView(frame: NSRect(origin: .zero, size: geometry.rect.size))
        view.onHover = onHover
        view.onClick = onClick
        // Приёмник файлов — родитель следящей вью, а не слой поверх неё: AppKit
        // ищет получателя сброса, поднимаясь от вью под курсором по родителям,
        // а слой сверху съел бы наведение и клик по челке.
        let dropper = FileDropView(frame: NSRect(origin: .zero, size: geometry.rect.size))
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

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
        override func mouseDown(with event: NSEvent) { onClick?() }
    }
}
