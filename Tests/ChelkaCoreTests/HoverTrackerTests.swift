import Testing
@testable import ChelkaCore

/// Наведение на челку раскрывало тонкую подсказку, но она закрывалась в тот
/// момент, когда курсор уходил С НЕЁ — то есть ровно тогда, когда он двигался
/// дальше, в саму панель. Дропдаун обязан оставаться открытым, пока курсор
/// внутри ЛЮБОЙ из двух зон, и закрываться только когда он вышел из обеих.
@Test func hoveringOnlyTheNotchCounts() {
    let t = HoverTracker().entering("notch")
    #expect(t.isHoveringAnything)
}

@Test func leavingTheNotchIntoThePanelStaysHovering() {
    let t = HoverTracker().entering("notch").entering("panel").leaving("notch")
    #expect(t.isHoveringAnything)
}

@Test func leavingBothStopsHovering() {
    let t = HoverTracker().entering("notch").entering("panel").leaving("notch").leaving("panel")
    #expect(!t.isHoveringAnything)
}

@Test func leavingARegionNeverEnteredChangesNothing() {
    let t = HoverTracker().entering("notch").leaving("panel")
    #expect(t.isHoveringAnything)
}

@Test func enteringTheSameRegionTwiceIsIdempotent() {
    let t = HoverTracker().entering("notch").entering("notch").leaving("notch")
    #expect(!t.isHoveringAnything)
}

@Test func startsEmpty() {
    #expect(!HoverTracker().isHoveringAnything)
}
