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
