import Foundation

/// Одна карточка за раз. Новое событие перезапускает таймер, а не плодит вторую;
/// событие меньшего приоритета не перебивает показанное более важное.
public struct ActivityQueue: Equatable, Sendable {
    public let current: ActivityEvent?
    public let deadline: Date?

    public init(current: ActivityEvent? = nil, deadline: Date? = nil) {
        self.current = current
        self.deadline = deadline
    }

    public func submitting(_ event: ActivityEvent, now: Date, panel: PanelState) -> ActivityQueue {
        guard panel != .expanded else { return self }
        if let shown = current, shown.kind > event.kind { return self }
        return ActivityQueue(current: event,
                             deadline: now.addingTimeInterval(Config.Activity.duration))
    }

    public func ticking(now: Date) -> ActivityQueue {
        guard let deadline, now >= deadline else { return self }
        return ActivityQueue()
    }
}
