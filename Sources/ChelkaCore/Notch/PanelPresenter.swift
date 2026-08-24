import AppKit

/// Окно панели с точки зрения представления. Протокол, а не сам `NotchPanel`,
/// ровно за одним: применение представления обязано проверяться тестом без
/// живого окна и без экрана.
@MainActor
public protocol PanelSurface: AnyObject {
    func place(at frame: CGRect)
    func show()
    func hide()
    func allowKeyboard(_ allowed: Bool)
    func takeKeyboard()
    func present(_ content: NSView)
}

/// Окно зоны-триггера с той же целью.
@MainActor
public protocol TriggerSurface: AnyObject {
    func setInteractive(_ enabled: Bool)
    func move(to rect: CGRect)
}

/// Применяет `PanelPresentation` к окнам. Единственное место, где состояние
/// панели превращается в вызовы AppKit; раньше это был приватный `switch`
/// внутри делегата, и проверить его было нечем.
@MainActor
public final class PanelPresenter {
    private let panel: PanelSurface
    private let trigger: TriggerSurface?
    private let makeContent: (PanelContent) -> NSView?

    /// Что уже нарисовано. Содержимое пересобирается только когда оно
    /// действительно поменялось: пересборка на каждый вызов обнуляла бы строку
    /// поиска, выделение и фокус, а на каждый тик таймера — перечитывала бы
    /// картинку карточки с диска (до сорока мегабайт, двенадцать раз за три
    /// секунды её жизни).
    private var appliedContent: PanelContent?
    private var appliedTriggerFrame: CGRect?

    /// `content` возвращает `nil`, если строить нечего (например, буфер ещё не
    /// поднят). Тогда прошлое содержимое остаётся на месте и попытка повторится
    /// на следующем применении, а не запоминается как выполненная.
    public init(panel: PanelSurface,
                trigger: TriggerSurface?,
                content: @escaping (PanelContent) -> NSView?) {
        self.panel = panel
        self.trigger = trigger
        self.makeContent = content
    }

    /// Забыть, что нарисовано. Нужно при смене геометрии: содержимое считает
    /// своё место от неё, и при переезде на другой экран его надо пересобрать,
    /// даже если состояние осталось тем же.
    public func invalidateContent() {
        appliedContent = nil
    }

    public func apply(_ presentation: PanelPresentation) {
        trigger?.setInteractive(presentation.triggerIsInteractive)
        moveTriggerIfNeeded(to: presentation.triggerFrame)
        // Разрешение снимаем ДО показа: иначе окно успевает остаться
        // клавиатурным на один проход цикла событий.
        panel.allowKeyboard(presentation.allowsKeyboard)
        rebuildContentIfNeeded(presentation.content)
        guard let frame = presentation.frame, presentation.isVisible else {
            panel.hide()
            return
        }
        // Размер до показа, а не после: иначе первый кадр рисуется по старой
        // рамке — именно так панель на запуске мелькала посреди строки меню.
        panel.place(at: frame)
        panel.show()
        if presentation.takesKeyboard { panel.takeKeyboard() }
    }

    private func rebuildContentIfNeeded(_ content: PanelContent) {
        guard content != appliedContent, let view = makeContent(content) else { return }
        appliedContent = content
        panel.present(view)
    }

    private func moveTriggerIfNeeded(to rect: CGRect) {
        guard rect != appliedTriggerFrame else { return }
        appliedTriggerFrame = rect
        trigger?.move(to: rect)
    }
}
