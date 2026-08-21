import Testing
import Foundation
@testable import ChelkaCore

private func fixtureLines() throws -> [String] {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/nowplaying-stream",
                                             withExtension: "jsonl"))
    return try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
}

@Test func replaysFixtureAndEndsPlaying() throws {
    var state = NowPlaying.empty
    for line in try fixtureLines() {
        if let parsed = NowPlayingLine.parse(line) { state = state.applying(parsed) }
    }
    #expect(state.title == "Sunflower")
    #expect(state.bundleIdentifier == "ru.yandex.desktop.music")
    #expect(state.isPlaying == true)
}

@Test func pauseDiffFlipsPlayingWithoutLosingTitle() throws {
    let lines = try fixtureLines()
    var state = NowPlaying.empty
    for line in lines.prefix(3) {
        if let parsed = NowPlayingLine.parse(line) { state = state.applying(parsed) }
    }
    #expect(state.isPlaying == false)
    #expect(state.title == "Sunflower")
}

@Test func fullSnapshotWithEmptyPayloadMeansNothingPlaying() {
    let line = try! #require(NowPlayingLine.parse(#"{"type":"data","diff":false,"payload":{}}"#))
    let state = NowPlaying.empty.applying(line)
    #expect(state.isEmpty)
}

@Test func fullSnapshotReplacesInsteadOfMerging() {
    var state = NowPlaying.empty
    state = state.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"Первый","artist":"А","playing":true}}"#)!)
    state = state.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"Второй","playing":true}}"#)!)
    #expect(state.title == "Второй")
    #expect(state.artist == nil)
}

@Test func diffMergesOnTop() {
    var state = NowPlaying.empty
    state = state.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"Первый","artist":"А","playing":true}}"#)!)
    state = state.applying(NowPlayingLine.parse(#"{"diff":true,"payload":{"playing":false}}"#)!)
    #expect(state.title == "Первый")
    #expect(state.artist == "А")
    #expect(state.isPlaying == false)
}

@Test func livePositionAdvancesWhilePlaying() {
    let anchor = Date(timeIntervalSince1970: 1000)
    let state = NowPlaying.empty.applying(NowPlayingLine.parse(#"""
    {"diff":false,"payload":{"title":"т","playing":true,"elapsedTime":16.0,"timestamp":"1970-01-01T00:16:40Z"}}
    """#)!)
    let position = try! #require(state.position(at: anchor.addingTimeInterval(5)))
    #expect(abs(position - 21.0) < 0.01)
}

@Test func livePositionIsFrozenWhilePaused() {
    let anchor = Date(timeIntervalSince1970: 1000)
    let state = NowPlaying.empty.applying(NowPlayingLine.parse(#"""
    {"diff":false,"payload":{"title":"т","playing":false,"elapsedTime":16.0,"timestamp":"1970-01-01T00:16:40Z"}}
    """#)!)
    #expect(state.position(at: anchor.addingTimeInterval(5)) == 16.0)
}

@Test func positionNeverExceedsDuration() {
    let state = NowPlaying.empty.applying(NowPlayingLine.parse(#"""
    {"diff":false,"payload":{"title":"т","playing":true,"elapsedTime":10.0,"duration":12.0,"timestamp":"1970-01-01T00:00:10Z"}}
    """#)!)
    let position = try! #require(state.position(at: Date(timeIntervalSince1970: 100)))
    #expect(position == 12.0)
}

@Test func replaysFixtureAndPositionReflectsTimestampOnlyUpdate() throws {
    var state = NowPlaying.empty
    for line in try fixtureLines() {
        if let parsed = NowPlayingLine.parse(line) { state = state.applying(parsed) }
    }
    // Последняя строка фикстуры несёт свежий timestamp (10:49:57Z) без elapsedTime.
    // Опорная пара должна остаться от предыдущей строки (36.670384 / 10:49:55Z),
    // поэтому позиция в момент реального прихода этой строки — 38.670384
    // (плюс двухсекундный разрыв), а не застрявшие на месте 36.670384.
    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-21T10:49:57Z"))
    let position = try #require(state.position(at: now))
    #expect(abs(position - 38.670384) < 0.01)
}

@Test func diffWithTimestampButNoElapsedTimeLeavesAnchorUnchanged() {
    var state = NowPlaying.empty
    state = state.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"т","playing":true,"elapsedTime":10.0,"timestamp":"1970-01-01T00:00:10Z"}}"#)!)
    state = state.applying(NowPlayingLine.parse(
        #"{"diff":true,"payload":{"timestamp":"1970-01-01T00:00:20Z"}}"#)!)
    #expect(state.elapsedAnchor == 10.0)
    #expect(state.anchorTimestamp == Date(timeIntervalSince1970: 10))
}

@Test func diffWithExplicitNullFieldsKeepsPreviousValuesWithoutCrashing() {
    // JSONSerialization представляет явный JSON null как NSNull — штатный способ
    // источника «очистить поле» в диффе, а не признак сломанного формата.
    // Разбор не должен падать и не должен подменять старое значение мусором.
    var state = NowPlaying.empty
    state = state.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"Первый","artist":"А","duration":180.0,"elapsedTime":10.0,"timestamp":"1970-01-01T00:00:10Z","playing":true}}"#)!)
    state = state.applying(NowPlayingLine.parse(
        #"{"diff":true,"payload":{"title":null,"duration":null,"elapsedTime":null,"playing":true}}"#)!)
    #expect(state.title == "Первый")
    #expect(state.artist == "А")
    #expect(state.duration == 180.0)
    #expect(state.elapsedAnchor == 10.0)
    #expect(state.anchorTimestamp == Date(timeIntervalSince1970: 10))
}

@Test func trackIdentityIgnoresContentItemIdentifier() {
    // Замер на фикстуре: contentItemIdentifier меняется при каждом обновлении состояния,
    // поэтому идентичность трека — это название плюс исполнитель.
    let a = NowPlaying.empty.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"т","artist":"и","contentItemIdentifier":"AAA"}}"#)!)
    let b = NowPlaying.empty.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"т","artist":"и","contentItemIdentifier":"BBB"}}"#)!)
    #expect(a.trackIdentity == b.trackIdentity)
}

// MARK: - Штамп времени

/// Проверено: разбор ISO8601 по умолчанию НЕ берёт дробные секунды, а адаптер
/// их присылает. Опорное время терялось, и живая позиция замирала у играющего
/// трека — молча.
@Test func fractionalSecondsInTimestampAreAccepted() throws {
    let state = NowPlaying.empty.applying(NowPlayingLine.parse(#"""
    {"diff":false,"payload":{"title":"т","playing":true,"elapsedTime":10.0,"timestamp":"1970-01-01T00:00:10.500Z"}}
    """#)!)
    #expect(state.anchorTimestamp != nil)
    let position = try #require(state.position(at: Date(timeIntervalSince1970: 20)))
    #expect(abs(position - 19.5) < 0.01)
}

@Test func unparsableTimestampIsReportedInsteadOfSilence() {
    var messages: [String] = []
    let line = NowPlayingLine.parse(#"""
    {"diff":false,"payload":{"title":"т","playing":true,"elapsedTime":10.0,"timestamp":"вчера"}}
    """#)!
    let state = NowPlaying.empty.applying(line, warn: { messages.append($0) })
    #expect(state.anchorTimestamp == nil)
    #expect(messages.count == 1)
}

@Test func plainTimestampStillParses() {
    #expect(NowPlaying.timestamp(from: "1970-01-01T00:00:10Z") == Date(timeIntervalSince1970: 10))
    #expect(NowPlaying.timestamp(from: "не время") == nil)
}

// MARK: - Пустая строка — это отсутствие значения, а не значение

@Test func emptyTitleIsTreatedAsMissing() {
    let state = NowPlaying.empty.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"","artist":"И","playing":true}}"#)!)
    #expect(state.title == nil)
    #expect(state.displayTitle == nil)
}

@Test func whitespaceOnlyTitleIsTreatedAsMissing() {
    let state = NowPlaying.empty.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"   ","artist":"И","playing":true}}"#)!)
    #expect(state.displayTitle == nil)
}

@Test func stateWithOnlyEmptyStringsCountsAsNothingPlaying() {
    let state = NowPlaying.empty.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"","artist":"","playing":true}}"#)!)
    #expect(state.isEmpty)
    #expect(state.trackIdentity == nil)
}

/// Заголовок и подзаголовок карточки. Если названия нет вовсе, исполнитель
/// встаёт заголовком ОДИН раз: раньше он стоял и заголовком, и подзаголовком.
@Test func displayLinesDoNotRepeatArtistTwice() {
    let state = NowPlaying(title: nil, artist: "И", album: nil, duration: nil,
                           elapsedAnchor: nil, anchorTimestamp: nil, isPlaying: true,
                           bundleIdentifier: nil, artworkData: nil)
    let lines = try! #require(state.displayLines)
    #expect(lines.headline == "И")
    #expect(lines.subheadline == nil)
}

@Test func displayLinesNeverStartWithAnEmptyFirstLine() {
    let state = NowPlaying(title: "", artist: "И", album: nil, duration: nil,
                           elapsedAnchor: nil, anchorTimestamp: nil, isPlaying: true,
                           bundleIdentifier: nil, artworkData: nil)
    let lines = try! #require(state.displayLines)
    #expect(lines.headline == "И")
}

@Test func trailingSpacesDoNotMakeANewTrack() {
    let a = NowPlaying.empty.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"Т ","artist":" И"}}"#)!)
    let b = NowPlaying.empty.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"Т","artist":"И"}}"#)!)
    #expect(a.trackIdentity == b.trackIdentity)
}

@Test func caseOnlyChangeDoesNotMakeANewTrack() {
    let a = NowPlaying.empty.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"Sunflower","artist":"Post Malone"}}"#)!)
    let b = NowPlaying.empty.applying(NowPlayingLine.parse(
        #"{"diff":false,"payload":{"title":"SUNFLOWER","artist":"post malone"}}"#)!)
    #expect(a.trackIdentity == b.trackIdentity)
}

@Test func parseRejectsGarbage() {
    #expect(NowPlayingLine.parse("не json") == nil)
    #expect(NowPlayingLine.parse("") == nil)
    #expect(NowPlayingLine.parse(#"{"diff":false}"#) == nil)
}
