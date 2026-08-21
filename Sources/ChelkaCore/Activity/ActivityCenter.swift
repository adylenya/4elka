import Foundation

/// Единственный владелец очереди карточек на всё приложение. Отдельный тип,
/// потому что поставщиков три — буфер, плеер, батареи — и две очереди сломали
/// бы приоритеты между ними (заряд важнее буфера, буфер важнее трека).
@MainActor
public final class ActivityCenter: ObservableObject {
    @Published public private(set) var queue = ActivityQueue()
    private let panelState: () -> PanelState

    public init(panelState: @escaping () -> PanelState) { self.panelState = panelState }

    public func submit(_ event: ActivityEvent, now: Date = Date()) {
        queue = queue.submitting(event, now: now, panel: panelState())
    }

    public func tick(now: Date = Date()) {
        queue = queue.ticking(now: now)
    }
}
