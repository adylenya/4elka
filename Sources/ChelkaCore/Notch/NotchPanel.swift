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

    /// Смена размера и положения — плавная. Раньше была мгновенной, и
    /// переход между наведением и раскрытой панелью выглядел рваным скачком.
    public func place(at frame: CGRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.Notch.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(frame, display: true)
        }
    }

    /// Появление плавное только когда окна ещё не было на экране: если оно
    /// уже видно и просто меняет размер (наведение → раскрытие), повторный
    /// цикл «спрятать и показать» заново дал бы лишнюю вспышку прозрачности.
    public func show() {
        guard !isVisible else {
            orderFrontRegardless()
            return
        }
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.Notch.animationDuration
            self.animator().alphaValue = 1
        }
    }

    /// Исчезновение — тоже плавное, и лишь затем окно реально снимается с
    /// экрана: иначе, читая его прозрачность в момент `orderOut`, AppKit
    /// начинал бы гасить уже пропавшее окно.
    public func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Config.Notch.animationDuration
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Обработчик завершения анимации типизирован как обычное
            // замыкание, а не как код на главном акторе — но AppKit
            // вызывает его на главном потоке, как и весь остальной цикл
            // анимации. `self` изолирован актором, поэтому явно, а не
            // молчаливым `@unchecked Sendable`.
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
                self.alphaValue = 1
            }
        })
    }

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
