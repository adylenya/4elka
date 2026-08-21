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

// ВАЖНО: каждый тест обязан удерживать координатор в переменной, а не выбрасывать
// его через `let (_, source, events) = make()`. Захват в координаторе слабый, и
// выброшенный координатор немедленно уничтожается — события не придут, а тест
// упадёт по причине, не имеющей отношения к проверяемому поведению.

@Test @MainActor func cardOnTrackChange() {
    let (coordinator, source, events) = make()
    defer { _ = coordinator }
    source.emit(state(title: "Первый", playing: true))
    source.emit(state(title: "Второй", playing: true))
    #expect(events().count == 2)
    #expect(events().last?.title == "Второй")
}

@Test @MainActor func cardOnPauseAndResume() {
    let (coordinator, source, events) = make()
    defer { _ = coordinator }
    source.emit(state(title: "Т", playing: true))
    source.emit(state(title: "Т", playing: false))
    source.emit(state(title: "Т", playing: true))
    #expect(events().count == 3)
}

@Test @MainActor func noCardOnPositionUpdatesOnly() {
    let (coordinator, source, events) = make()
    defer { _ = coordinator }
    source.emit(state(title: "Т", playing: true, elapsed: 5))
    source.emit(state(title: "Т", playing: true, elapsed: 10))
    source.emit(state(title: "Т", playing: true, elapsed: 15))
    #expect(events().count == 1)
}

@Test @MainActor func releasedCoordinatorStopsReceivingEvents() {
    // Это и есть то поведение, которое цикл ссылок сделал бы непроверяемым.
    let source = FakeSource()
    var events: [ActivityEvent] = []
    do {
        let c = MediaCoordinator(source: source, panelState: { .hidden },
                                submitActivity: { events.append($0) })
        c.start()
        source.emit(state(title: "Первый", playing: true))
        #expect(events.count == 1)
    }
    source.emit(state(title: "Второй", playing: true))
    #expect(events.count == 1)
}

@Test @MainActor func sameTrackFiresAgainAfterNothingPlaying() {
    let (coordinator, source, events) = make()
    defer { _ = coordinator }
    source.emit(state(title: "Т", playing: true))
    source.emit(.empty)
    source.emit(state(title: "Т", playing: true))
    #expect(events().count == 2)
}

@Test @MainActor func noCardWhenNothingIsPlaying() {
    let (coordinator, source, events) = make()
    defer { _ = coordinator }
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

// MARK: - Обложка

private func stateWithArtwork(_ data: Data, elapsed: TimeInterval) -> NowPlaying {
    NowPlaying(title: "Т", artist: "И", album: nil, duration: 100,
               elapsedAnchor: elapsed, anchorTimestamp: Date(timeIntervalSince1970: 0),
               isPlaying: true, bundleIdentifier: "ru.yandex.desktop.music", artworkData: data)
}

/// Битая обложка разбиралась заново на каждом обновлении позиции — то есть раз
/// в секунду один и тот же мегабайт.
@Test @MainActor func brokenArtworkIsDecodedOnlyOncePerTrack() {
    let source = FakeSource()
    var attempts = 0
    let c = MediaCoordinator(source: source, panelState: { .hidden },
                            submitActivity: { _ in },
                            decodeArtwork: { _ in attempts += 1; return nil })
    c.start()
    let broken = Data([0x00, 0x01, 0x02])
    for elapsed in [1.0, 2.0, 3.0] { source.emit(stateWithArtwork(broken, elapsed: elapsed)) }
    #expect(attempts == 1)
    #expect(c.artwork == nil)
}

/// Новый трек — новая попытка: отказ помнится ровно для одной идентичности.
@Test @MainActor func nextTrackGetsItsOwnArtworkAttempt() {
    let source = FakeSource()
    var attempts = 0
    let c = MediaCoordinator(source: source, panelState: { .hidden },
                            submitActivity: { _ in },
                            decodeArtwork: { _ in attempts += 1; return nil })
    c.start()
    source.emit(stateWithArtwork(Data([0x00]), elapsed: 1))
    source.emit(NowPlaying(title: "Другой", artist: "И", album: nil, duration: 100,
                           elapsedAnchor: 1, anchorTimestamp: nil, isPlaying: true,
                           bundleIdentifier: nil, artworkData: Data([0x00])))
    #expect(attempts == 2)
}

/// Пустое название и непустой исполнитель давали карточку с пустой первой
/// строкой — она читается как поломка приложения.
@Test func activityEventNeverHasEmptyTitle() {
    let e = try! #require(MediaCoordinator.activityEvent(for: state(title: "", artist: "И",
                                                                   playing: true)))
    #expect(e.title == "И")
    #expect(e.subtitle == nil)
}

/// Названия нет вовсе — исполнитель встаёт заголовком один раз, а не дважды.
@Test func activityEventDoesNotRepeatArtistInBothLines() {
    let e = try! #require(MediaCoordinator.activityEvent(for: state(title: nil, artist: "И",
                                                                   playing: true)))
    #expect(e.title == "И")
    #expect(e.subtitle == nil)
}

@Test func activityEventIsNothingWhenBothLinesAreBlank() {
    #expect(MediaCoordinator.activityEvent(for: state(title: "  ", artist: "", playing: true)) == nil)
}

@Test func activityEventCarriesArtistAsSubtitle() {
    let e = try! #require(MediaCoordinator.activityEvent(for: state(title: "Т", artist: "И", playing: true)))
    #expect(e.title == "Т")
    #expect(e.subtitle == "И")
    #expect(e.kind == .track)
}
