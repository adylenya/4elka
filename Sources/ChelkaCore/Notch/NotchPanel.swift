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
///
/// Рамку окно себе не считает: её считает `PanelFrames`, а ставит
/// `PanelPresenter`. Раньше расчёт жил тут же и разошёлся с раскладкой.
@MainActor
public final class NotchPanel: NSPanel, PanelSurface {
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

    // MARK: - PanelSurface

    public func place(at frame: CGRect) {
        setFrame(frame, display: true, animate: false)
    }

    public func show() { orderFrontRegardless() }

    public func hide() { orderOut(nil) }

    /// Разрешить или запретить окну становиться клавиатурным.
    ///
    /// Если разрешение снимается, а окно уже успело стать key — окно уходит с
    /// экрана. `resignKey()` для этого не годится: он только рассылает
    /// уведомление и клавиатурный статус никому не передаёт, то есть окно
    /// продолжает перехватывать набор текста. Реально отпустить клавиатуру
    /// умеет лишь уход окна с экрана — AppKit сам выбирает следующее key-окно.
    /// Показать окно снова, если оно нужно, — дело `PanelPresenter`: он зовёт
    /// `show()` после `allowKeyboard(_:)`, и окно возвращается уже без клавиатуры.
    public func allowKeyboard(_ allowed: Bool) {
        keyboardAllowed = allowed
        if !allowed, isKeyWindow { orderOut(nil) }
    }

    public func takeKeyboard() { makeKey() }

    public func present(_ content: NSView) { contentView = content }
}
