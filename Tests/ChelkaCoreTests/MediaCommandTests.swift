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
