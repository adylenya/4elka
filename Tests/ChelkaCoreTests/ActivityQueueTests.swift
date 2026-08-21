import Testing
import Foundation
@testable import ChelkaCore

private func ev(_ kind: ActivityEvent.Kind, _ title: String) -> ActivityEvent {
    ActivityEvent(id: UUID(), kind: kind, title: title, subtitle: nil, imageBlobName: nil)
}
private let t0 = Date(timeIntervalSince1970: 1000)

@Test func submittingShowsEventAndSetsDeadline() {
    let q = ActivityQueue().submitting(ev(.track, "трек"), now: t0, panel: .hidden)
    #expect(q.current?.title == "трек")
    #expect(q.deadline == t0.addingTimeInterval(Config.Activity.duration))
}

@Test func secondEventRestartsTimerInsteadOfStackingCards() {
    let q = ActivityQueue()
        .submitting(ev(.track, "первый"), now: t0, panel: .hidden)
        .submitting(ev(.track, "второй"), now: t0.addingTimeInterval(1), panel: .hidden)
    #expect(q.current?.title == "второй")
    #expect(q.deadline == t0.addingTimeInterval(1 + Config.Activity.duration))
}

@Test func suppressedWhilePanelExpanded() {
    let q = ActivityQueue().submitting(ev(.clipboard, "текст"), now: t0, panel: .expanded)
    #expect(q.current == nil)
}

@Test func higherPriorityWinsOverLowerWhileCardIsVisible() {
    let q = ActivityQueue()
        .submitting(ev(.battery, "мало заряда"), now: t0, panel: .hidden)
        .submitting(ev(.track, "трек"), now: t0.addingTimeInterval(1), panel: .hidden)
    #expect(q.current?.title == "мало заряда")
}

@Test func lowerPriorityIsReplacedByHigher() {
    let q = ActivityQueue()
        .submitting(ev(.track, "трек"), now: t0, panel: .hidden)
        .submitting(ev(.battery, "мало заряда"), now: t0.addingTimeInterval(1), panel: .hidden)
    #expect(q.current?.title == "мало заряда")
}

@Test func tickHidesCardAfterDeadline() {
    let q = ActivityQueue().submitting(ev(.track, "трек"), now: t0, panel: .hidden)
    #expect(q.ticking(now: t0.addingTimeInterval(1)).current != nil)
    #expect(q.ticking(now: t0.addingTimeInterval(Config.Activity.duration + 0.1)).current == nil)
}

@Test func tickOnEmptyQueueIsNoOp() {
    #expect(ActivityQueue().ticking(now: t0) == ActivityQueue())
}
