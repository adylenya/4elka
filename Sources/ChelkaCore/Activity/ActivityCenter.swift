import Foundation

/// Единственный владелец очереди карточек на всё приложение. Отдельный тип,
/// потому что поставщиков три — буфер, плеер, батареи — и две очереди сломали
/// бы приоритеты между ними (заряд важнее буфера, буфер важнее трека).
@MainActor
public final class ActivityCenter: ObservableObject {
    @Published public private(set) var queue = ActivityQueue()
    private let panelState: () -> PanelState
    private let settings: () -> Settings

    /// Настройки читаются замыканием, а не копируются при создании: человек
    /// правит их в открытом окне, и следующее же событие обязано считаться с
    /// новым значением, без перезапуска приложения.
    public init(panelState: @escaping () -> PanelState,
                settings: @escaping () -> Settings = { .defaults }) {
        self.panelState = panelState
        self.settings = settings
    }

    public func submit(_ event: ActivityEvent, now: Date = Date()) {
        let current = settings()
        // Выключенный источник отбрасывается на входе, а не проигрывает по
        // приоритету: иначе событие, оказавшееся приоритетнее показанного,
        // всё равно перебило бы его, будучи выключенным.
        guard current.allowsCard(event.kind) else { return }
        queue = queue.submitting(event, now: now, panel: panelState(),
                                 duration: current.activityDuration)
    }

    public func tick(now: Date = Date()) {
        queue = queue.ticking(now: now)
    }

    /// Погасить очередь немедленно. Зовётся при выходе из состояния «карточка»:
    /// иначе уже летящее событие продолжало тикать под раскрытой панелью и
    /// пыталось нарисоваться поверх сетки истории.
    public func clear() {
        queue = ActivityQueue()
    }
}
