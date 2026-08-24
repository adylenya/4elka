import AppKit

/// Что должно быть нарисовано в панели. Отдельное значение, а не просто
/// состояние: карточка рисуется по паре (состояние, очередь), и без второй
/// половины пары получалось состояние, из которого приложение было невозможно
/// вывести — карточка затирала сетку истории и не возвращала её никогда.
///
/// `eventID` держим здесь же: содержимое считается тем же, пока то же событие,
/// и таймер, тикающий четыре раза в секунду, больше не пересобирает дерево вью
/// и не перечитывает картинку с диска на каждом тике.
public struct PanelContent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Чёрная фигура с тонкой подсказкой: скрытое и наведение.
        case hint
        /// Карточка события.
        case activity
        /// Сетка истории и полоса полки.
        case history

        /// Начинается ли этот вид содержимого чёрной фигурой высотой челки.
        /// Список исчерпывающий намеренно: новый вид содержимого заставит
        /// принять решение здесь, а не тихо залить верх панели стеклом —
        /// именно так челка и превратилась в чёрный укус в раскрытом состоянии.
        public var drawsNotchFigure: Bool {
            switch self {
            // Фигура чёрная целиком: и полоса сверху, и тело под ней.
            case .hint, .activity: return true
            // Полоса сверху чёрная, стекло достаётся содержимому ниже.
            case .history: return true
            }
        }
    }

    public let kind: Kind
    public let eventID: UUID?

    public init(kind: Kind, eventID: UUID? = nil) {
        self.kind = kind
        self.eventID = eventID
    }
}

/// Как окна должны выглядеть в данном состоянии — чистое значение, целиком
/// проверяемое тестом. Применяет его `PanelPresenter`, и только он трогает
/// AppKit.
public struct PanelPresentation: Equatable, Sendable {
    /// Рамка окна панели. `nil` — панель убрать с экрана.
    public let frame: CGRect?
    /// Рамка окна зоны-триггера: она переезжает вместе с панелью, иначе после
    /// смены экрана наведение перестаёт работать, а невидимое окно остаётся
    /// съедать нажатия на старом месте.
    public let triggerFrame: CGRect
    public let isVisible: Bool
    /// Разрешено ли окну становиться клавиатурным.
    public let allowsKeyboard: Bool
    /// Надо ли забрать клавиатуру прямо сейчас.
    public let takesKeyboard: Bool
    /// Принимает ли зона-триггер мышь. Она принимает её всегда, пока есть
    /// экран: отключение зоны в раскрытом состоянии убирало единственный
    /// источник клика, и выйти из раскрытой панели было нечем.
    public let triggerIsInteractive: Bool
    public let content: PanelContent

    /// Рисуется ли полоса высотой челки чёрной фигурой. Обязана рисоваться в
    /// каждом видимом состоянии: все они прижаты к верху экрана, и стекло в
    /// верхних 38 точках превращает челку в чёрный укус посреди панели.
    public var drawsNotchFigure: Bool { isVisible && content.kind.drawsNotchFigure }

    public static func make(state: PanelState,
                            event: ActivityEvent?,
                            geometry: NotchGeometry) -> PanelPresentation {
        let frame = PanelFrames.frame(for: state, geometry: geometry)
        let visible = frame != nil
        return PanelPresentation(
            frame: frame,
            triggerFrame: geometry.rect,
            isVisible: visible,
            allowsKeyboard: NotchPanel.allowsKeyboard(in: state),
            takesKeyboard: visible && NotchPanel.allowsKeyboard(in: state),
            triggerIsInteractive: geometry.isUsable,
            content: content(state: state, event: event))
    }

    /// Содержимое как функция пары (состояние, очередь).
    ///
    /// Раскрытая панель показывает историю ВСЕГДА, даже если в очереди ещё
    /// висит карточка: именно подмена сетки истории чёрной фигурой карточки
    /// создавала состояние без выхода. А состояние «карточка» с пустой очередью
    /// не имеет права рисовать карточку — рисовать в этот момент нечего.
    private static func content(state: PanelState, event: ActivityEvent?) -> PanelContent {
        switch state {
        case .expanded:
            return PanelContent(kind: .history)
        case .activity:
            guard let event else { return PanelContent(kind: .hint) }
            return PanelContent(kind: .activity, eventID: event.id)
        case .hidden, .peek:
            // Скрытое и наведение показывают одно и то же, поэтому проход
            // мыши мимо челки не пересобирает содержимое ни разу.
            return PanelContent(kind: .hint)
        }
    }
}
