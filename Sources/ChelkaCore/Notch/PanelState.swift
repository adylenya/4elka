/// Видимое состояние панели над челкой.
public enum PanelState: Equatable {
    case hidden, peek, activity, expanded
}

/// Иммутабельный автомат: каждый переход возвращает новый экземпляр.
public struct PanelStateMachine: Equatable {
    public let state: PanelState

    public init(state: PanelState = .hidden) { self.state = state }

    public func hovering(_ isInside: Bool) -> PanelStateMachine {
        switch state {
        case .expanded, .activity: return self
        case .hidden: return isInside ? PanelStateMachine(state: .peek) : self
        case .peek: return isInside ? self : PanelStateMachine(state: .hidden)
        }
    }

    public func clicked() -> PanelStateMachine {
        state == .expanded ? PanelStateMachine(state: .hidden)
                           : PanelStateMachine(state: .expanded)
    }

    public func showingActivity() -> PanelStateMachine {
        state == .expanded ? self : PanelStateMachine(state: .activity)
    }

    public func activityFinished() -> PanelStateMachine {
        state == .activity ? PanelStateMachine(state: .hidden) : self
    }

    public func dismissed() -> PanelStateMachine {
        PanelStateMachine(state: .hidden)
    }
}
