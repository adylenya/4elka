import Testing
import Foundation
@testable import ChelkaCore

@Test func commandCodesMatchAdapterTable() {
    #expect(MediaCommand.play.rawValue == 0)
    #expect(MediaCommand.pause.rawValue == 1)
    #expect(MediaCommand.toggle.rawValue == 2)
    #expect(MediaCommand.next.rawValue == 4)
    #expect(MediaCommand.previous.rawValue == 5)
}

@Test func lineBufferSplitsChunksIntoWholeLines() {
    var buffer = LineBuffer()
    #expect(buffer.appending(Data("{\"a\":1}\n{\"b\"".utf8)) == ["{\"a\":1}"])
    #expect(buffer.appending(Data(":2}\n".utf8)) == ["{\"b\":2}"])
}

@Test func lineBufferHoldsIncompleteLine() {
    var buffer = LineBuffer()
    #expect(buffer.appending(Data("частичная".utf8)).isEmpty)
}

@Test func lineBufferSkipsEmptyLines() {
    var buffer = LineBuffer()
    #expect(buffer.appending(Data("\n\nx\n".utf8)) == ["x"])
}

@Test func lineBufferDropsRunawayInputInsteadOfGrowingForever() {
    var buffer = LineBuffer()
    let huge = Data(repeating: UInt8(ascii: "a"), count: Config.Media.maxPendingBytes + 1)
    #expect(buffer.appending(huge).isEmpty)
    // Буфер сброшен, дальше работает как обычно.
    #expect(buffer.appending(Data("снова\n".utf8)) == ["снова"])
}

/// Обложка приходит в потоке как base64, и картинка на 800 КБ даёт строку под
/// 1,1 МБ. Целая строка обязана дойти целиком, каким бы длинной она ни была:
/// порог существует против потока БЕЗ переводов строки, а не против длинных строк.
@Test func lineBufferDeliversWholeOversizedLine() {
    var buffer = LineBuffer()
    let big = String(repeating: "a", count: Config.Media.maxPendingBytes + 1)
    #expect(buffer.appending(Data("\(big)\n".utf8)) == [big])
}

@Test func lineBufferKeepsGoodLineThatCameTogetherWithARunawayOne() {
    // Проверка порога ДО нарезки выбрасывала кусок целиком — вместе с валидной
    // строкой, пришедшей в нём же.
    var buffer = LineBuffer()
    let runaway = String(repeating: "a", count: Config.Media.maxPendingBytes + 1)
    #expect(buffer.appending(Data("{\"a\":1}\n\(runaway)".utf8)) == ["{\"a\":1}"])
}

@Test func lineBufferKeepsGoodLineThatCameWithTailOfALongLine() {
    // Длинная строка двумя куском: с её хвостом терялась и нормальная строка,
    // пришедшая в том же куске.
    var buffer = LineBuffer()
    let half = String(repeating: "a", count: Config.Media.maxPendingBytes / 2 + 1)
    #expect(buffer.appending(Data(half.utf8)).isEmpty)
    let lines = buffer.appending(Data("\(half)\n{\"b\":2}\n".utf8))
    #expect(lines.count == 2)
    #expect(lines.last == "{\"b\":2}")
}

@Test func lineBufferComplainsAboutBrokenUtf8InsteadOfDroppingItSilently() {
    final class Log: @unchecked Sendable { var messages: [String] = [] }
    let log = Log()
    var buffer = LineBuffer(warn: { log.messages.append($0) })
    var chunk = Data([0xFF, 0xFE, 0xFF])
    chunk.append(Data("\n{\"a\":1}\n".utf8))
    // Битая строка выброшена, но здоровая рядом с ней доехала, и о потере сказано.
    #expect(buffer.appending(chunk) == ["{\"a\":1}"])
    #expect(log.messages.count == 1)
}

// MARK: - Хвост потока ошибок

@Test func errorTailKeepsOnlyTheLastLines() {
    var tail = ErrorTail()
    for i in 1...(Config.Media.errorTailLines + 3) {
        tail.appending(Data("строка \(i)\n".utf8))
    }
    let text = try! #require(tail.text)
    #expect(!text.contains("строка 1\n"))
    #expect(text.contains("строка \(Config.Media.errorTailLines + 3)"))
    #expect(text.components(separatedBy: "строка").count - 1 == Config.Media.errorTailLines)
}

@Test func errorTailIsNothingWhenAdapterSaidNothing() {
    var tail = ErrorTail()
    #expect(tail.text == nil)
    tail.appending(Data("недописанная строка".utf8))
    // Недособранная строка — ещё не строка: ждём перевода строки.
    #expect(tail.text == nil)
}

@Test func restartPolicyGrowsDelayAndCapsIt() {
    var policy = RestartPolicy.initial
    #expect(policy.delay == Config.Media.restartDelayInitial)
    for _ in 0..<10 { policy = policy.afterExit(livedFor: 0) }
    #expect(policy.delay == Config.Media.restartDelayMax)
}

@Test func restartPolicyResetsAfterHealthyRun() {
    var policy = RestartPolicy.initial.afterExit(livedFor: 0).afterExit(livedFor: 0)
    #expect(policy.delay > Config.Media.restartDelayInitial)
    policy = policy.afterExit(livedFor: Config.Media.healthyRunGrace)
    #expect(policy == .initial)
}

@Test func restartPolicyGivesUpAfterRepeatedInstantDeaths() {
    // Так выглядит отсутствующий или сломанный адаптер: perl запускается,
    // но умирает сразу. Бесконечно дёргать его нельзя.
    var policy = RestartPolicy.initial
    for _ in 0..<Config.Media.maxImmediateFailures { policy = policy.afterExit(livedFor: 0) }
    #expect(policy.shouldGiveUp)
}

@Test func restartPolicyDoesNotGiveUpWhileRunsAreHealthy() {
    var policy = RestartPolicy.initial
    for _ in 0..<10 { policy = policy.afterExit(livedFor: Config.Media.healthyRunGrace + 1) }
    #expect(!policy.shouldGiveUp)
}

// MARK: - Осиротевшие процессы адаптера

@Test func orphanScanPicksOnlyOurOwnAbandonedAdapters() {
    // Замерено 21.08: адаптер переживает смерть хозяина. Он умирает только при
    // следующей записи в закрытую трубу, а пишет — лишь когда меняется
    // состояние плеера. Значит после прибитого приложения процесс висит в
    // системе неограниченно долго, держа подписку на поток.
    let script = "/Users/x/4elka/vendor/mediaremote-adapter/bin/mediaremote-adapter.pl"
    let ps = """
    86975     1 /usr/bin/perl \(script) /Users/x/4elka/vendor/build/MediaRemoteAdapter.framework stream
    86976  4242 /usr/bin/perl \(script) /Users/x/4elka/vendor/build/MediaRemoteAdapter.framework stream
    86977     1 /usr/bin/perl /Users/other/tool/mediaremote-adapter.pl /Users/other/f stream
    86978     1 /usr/bin/swift build \(script)
    """
    let found = AdapterOrphans.pids(inProcessList: ps, scriptPath: script)
    // 86975 — наш и осиротел. 86976 живой ребёнок чужого экземпляра: не трогаем.
    // 86977 — другой адаптер, не наш. 86978 — не perl, это компилятор: на таком
    // шаблоне однажды уже убили сборку соседнего агента.
    #expect(found == [86975])
}

@Test func orphanScanIgnoresGarbageLines() {
    let script = "/tmp/a/mediaremote-adapter.pl"
    #expect(AdapterOrphans.pids(inProcessList: "", scriptPath: script).isEmpty)
    #expect(AdapterOrphans.pids(inProcessList: "мусор\n\n  \n", scriptPath: script).isEmpty)
    #expect(AdapterOrphans.pids(inProcessList: "нету 1 /usr/bin/perl \(script) stream",
                                scriptPath: script).isEmpty)
}

@Test func sweepTerminatesEveryOrphanItFound() {
    let script = "/tmp/a/mediaremote-adapter.pl"
    let ps = """
    11     1 /usr/bin/perl \(script) /tmp/a/f stream
    12     1 /usr/bin/perl \(script) /tmp/a/f stream
    13   999 /usr/bin/perl \(script) /tmp/a/f stream
    """
    final class Killed: @unchecked Sendable { var pids: [Int32] = [] }
    let killed = Killed()
    let swept = AdapterOrphans.sweep(scriptPath: script,
                                     processList: { ps },
                                     terminate: { killed.pids.append($0) })
    #expect(swept == [11, 12])
    #expect(killed.pids == [11, 12])
}

@Test func orphanScanSurvivesDoubleSpacesInsidePath() {
    // Проверено: если хвост строки `ps` пересклеить через один пробел, корень
    // проекта с двойным пробелом в имени каталога перестаёт совпадать — и
    // брошенные процессы не находятся вовсе.
    let script = "/Users/x/4elka  копия/vendor/mediaremote-adapter/bin/mediaremote-adapter.pl"
    let framework = "/Users/x/4elka  копия/vendor/build/MediaRemoteAdapter.framework"
    let ps = "86975     1 /usr/bin/perl \(script) \(framework) stream"
    #expect(AdapterOrphans.pids(inProcessList: ps, scriptPath: script) == [86975])
}

@Test func sweepDoesNothingWhenProcessListIsUnavailable() {
    // `ps` не запустился — это не повод падать и не повод гасить наугад.
    final class Killed: @unchecked Sendable { var count = 0 }
    let killed = Killed()
    let swept = AdapterOrphans.sweep(scriptPath: "/tmp/a.pl",
                                     processList: { nil },
                                     terminate: { _ in killed.count += 1 })
    #expect(swept.isEmpty)
    #expect(killed.count == 0)
}
