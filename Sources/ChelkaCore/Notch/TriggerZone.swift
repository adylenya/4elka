import AppKit

/// Прозрачное окно ровно по челке, которое ловит наведение и клик, когда
/// панель скрыта (и её `resize(to:1pt height)` делает нечувствительной к мыши
/// на всей своей площади). Без этого окна навести на схлопнутую челку и
/// поймать hover/клик было бы нечем.
public final class TriggerZone {
    private let window: NSPanel
    private let onHover: (Bool) -> Void
    private let onClick: () -> Void

    public init(geometry: NotchGeometry,
                onHover: @escaping (Bool) -> Void,
                onClick: @escaping () -> Void) {
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
        window.contentView = view
        window.orderFrontRegardless()
    }

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
