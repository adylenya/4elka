import Testing
import Foundation
@testable import ChelkaCore

private final class FakeSource: MediaSource {
    var onState: ((NowPlaying) -> Void)?
    var onUnavailable: (() -> Void)?
    var sent: [MediaCommand] = []
    func start() {}
    func stop() {}
    func send(_ command: MediaCommand) { sent.append(command) }
    func emit(_ s: NowPlaying) { onState?(s) }
}

private func state(title: String?, artist: String? = "и", playing: Bool,
                   elapsed: TimeInterval? = nil) -> NowPlaying {
    NowPlaying(title: title, artist: artist, album: nil, duration: 100,
               elapsedAnchor: elapsed, anchorTimestamp: Date(timeIntervalSince1970: 0),
               isPlaying: playing, bundleIdentifier: "ru.yandex.desktop.music", artworkData: nil)
}

@MainActor
private func make() -> (MediaCoordinator, FakeSource, () -> [ActivityEvent]) {
    let source = FakeSource()
    var events: [ActivityEvent] = []
    let c = MediaCoordinator(source: source, panelState: { .hidden },
                            submitActivity: { events.append($0) })
    c.start()
    return (c, source, { events })
}

@Test @MainActor func cardOnTrackChange() {
    let (_, source, events) = make()
    source.emit(state(title: "Первый", playing: true))
    source.emit(state(title: "Второй", playing: true))
    #expect(events().count == 2)
    #expect(events().last?.title == "Второй")
}

@Test @MainActor func cardOnPauseAndResume() {
    let (_, source, events) = make()
    source.emit(state(title: "Т", playing: true))
    source.emit(state(title: "Т", playing: false))
    source.emit(state(title: "Т", playing: true))
    #expect(events().count == 3)
}

@Test @MainActor func noCardOnPositionUpdatesOnly() {
    let (_, source, events) = make()
    source.emit(state(title: "Т", playing: true, elapsed: 5))
    source.emit(state(title: "Т", playing: true, elapsed: 10))
    source.emit(state(title: "Т", playing: true, elapsed: 15))
    #expect(events().count == 1)
}

@Test @MainActor func noCardWhenNothingIsPlaying() {
    let (_, source, events) = make()
    source.emit(.empty)
    #expect(events().isEmpty)
}

@Test @MainActor func forwardsCommands() {
    let (c, source, _) = make()
    c.send(.next)
    c.send(.toggle)
    #expect(source.sent == [.next, .toggle])
}

@Test @MainActor func marksUnavailableWhenAdapterFails() {
    let source = FakeSource()
    let c = MediaCoordinator(source: source, panelState: { .hidden }, submitActivity: { _ in })
    c.start()
    source.onUnavailable?()
    #expect(!c.isAvailable)
}

@Test func activityEventCarriesArtistAsSubtitle() {
    let e = try! #require(MediaCoordinator.activityEvent(for: state(title: "Т", artist: "И", playing: true)))
    #expect(e.title == "Т")
    #expect(e.subtitle == "И")
    #expect(e.kind == .track)
}
