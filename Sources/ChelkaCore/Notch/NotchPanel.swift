import AppKit

/// Окно панели, растущей вниз от челки.
///
/// Клавиатуру окно может забрать только в раскрытом состоянии, где живёт
/// поле поиска по истории — `canBecomeKey` зависит от состояния, а не
/// возвращает `true` безусловно. Раньше было наоборот, и выезжающая карточка
/// перехватывала набор текста у человека, который в этот момент печатал.
/// Панель при этом не забирает активацию у чужого приложения: за это
/// отвечают стиль `.nonactivatingPanel` здесь и `setActivationPolicy(.accessory)`
/// в точке входа приложения.
@MainActor
public final class NotchPanel: NSPanel {
    /// Разрешение брать клавиатуру нужно ровно в одном состоянии — раскрытом,
    /// где есть поле поиска. Раньше оно выдавалось всегда, и выезжающая карточка
    /// перехватывала набор текста у человека, который в этот момент печатал.
    /// `nonisolated`, потому что это чистая функция состояния: она не трогает
    /// ни окно, ни его поля, и тест обязан звать её без главного актора.
    public nonisolated static func allowsKeyboard(in state: PanelState) -> Bool {
        state == .expanded
    }

    private var keyboardAllowed = false
    public override var canBecomeKey: Bool { keyboardAllowed }
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
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    /// Разрешить или запретить окну становиться клавиатурным. Если разрешение
    /// снимается, а окно уже успело стать key — отдаём фокус немедленно, а не
    /// ждём следующего клика в чужом приложении.
    public func setKeyboardAllowed(_ allowed: Bool) {
        keyboardAllowed = allowed
        if !allowed, isKeyWindow { resignKey() }
    }

    /// Панель растёт вниз от верхнего края экрана, поэтому меняем и origin, и size.
    public func resize(to size: CGSize, geometry: NotchGeometry) {
        let frame = CGRect(x: geometry.rect.midX - size.width / 2,
                          y: geometry.rect.maxY - size.height,
                          width: size.width, height: size.height)
        setFrame(frame, display: true, animate: false)
    }
}
