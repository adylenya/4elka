import AppKit

/// Окно панели, растущей вниз от челки.
///
/// `canBecomeKey` обязан быть `true` — иначе поиск по истории (следующие
/// задачи) не сможет принять ни одного нажатия клавиши. Панель при этом не
/// забирает активацию у чужого приложения: за это отвечают стиль
/// `.nonactivatingPanel` здесь и `setActivationPolicy(.accessory)` в точке
/// входа приложения.
public final class NotchPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public init(geometry: NotchGeometry) {
        super.init(contentRect: geometry.rect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    /// Панель растёт вниз от верхнего края экрана, поэтому меняем и origin, и size.
    public func resize(to size: CGSize, geometry: NotchGeometry) {
        let frame = CGRect(x: geometry.rect.midX - size.width / 2,
                          y: geometry.rect.maxY - size.height,
                          width: size.width, height: size.height)
        setFrame(frame, display: true, animate: false)
    }
}
