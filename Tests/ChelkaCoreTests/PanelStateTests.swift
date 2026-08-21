import Testing
@testable import ChelkaCore

@Test func hoverRaisesHiddenToPeekAndBack() {
    let m = PanelStateMachine(state: .hidden)
    #expect(m.hovering(true).state == .peek)
    #expect(m.hovering(true).hovering(false).state == .hidden)
}

@Test func clickTogglesExpanded() {
    #expect(PanelStateMachine(state: .hidden).clicked().state == .expanded)
    #expect(PanelStateMachine(state: .peek).clicked().state == .expanded)
    #expect(PanelStateMachine(state: .expanded).clicked().state == .hidden)
}

@Test func hoverDoesNotDisturbExpanded() {
    let m = PanelStateMachine(state: .expanded)
    #expect(m.hovering(false).state == .expanded)
    #expect(m.hovering(true).state == .expanded)
}

@Test func activityIsSuppressedWhileExpanded() {
    #expect(PanelStateMachine(state: .expanded).showingActivity().state == .expanded)
    #expect(PanelStateMachine(state: .hidden).showingActivity().state == .activity)
}

@Test func activityReturnsToHidden() {
    #expect(PanelStateMachine(state: .activity).activityFinished().state == .hidden)
    #expect(PanelStateMachine(state: .expanded).activityFinished().state == .expanded)
}

@Test func dismissAlwaysHides() {
    #expect(PanelStateMachine(state: .expanded).dismissed().state == .hidden)
}
