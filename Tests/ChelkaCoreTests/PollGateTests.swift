import Testing
import Foundation
@testable import ChelkaCore

// MARK: - Замок и старшинство опросов

@Test func gateRefusesASecondPollWhileTheFirstIsRunning() {
    // Без замка повисшая утилита занимала поток намертво, а таймер добавлял по
    // такому потоку в минуту: за час шестьдесят мёртвых потоков.
    let gate = PollGate()
    let first = try! #require(gate.starting())
    #expect(first.gate.isBusy)
    #expect(first.gate.starting() == nil)
}

@Test func gateOpensAgainAfterTheRunningPollFinishes() {
    let gate = PollGate()
    let first = try! #require(gate.starting())
    let after = first.gate.finishing(first.generation)
    #expect(after.isFresh)
    #expect(!after.gate.isBusy)
    #expect(after.gate.starting() != nil)
}

@Test func laggingPollIsDiscardedSoFreshDataSurvives() {
    // Медленный опрос, доехавший последним, иначе перезаписал бы свежий список
    // устаревшим — на минуту, до следующего тика.
    var gate = PollGate()
    let first = try! #require(gate.starting())
    gate = first.gate.finishing(first.generation).gate
    let second = try! #require(gate.starting())
    gate = second.gate.finishing(second.generation).gate

    // Пришёл результат ПЕРВОГО опроса, когда второй уже применён.
    let late = gate.finishing(first.generation)
    #expect(!late.isFresh)
}

@Test func resultOfALaggingPollDoesNotUnlockTheGate() {
    // Замок снимает только тот опрос, который начинали последним: иначе
    // отставший результат открыл бы дорогу второму опросу поверх идущего.
    let gate = PollGate()
    let first = try! #require(gate.starting())
    let afterLate = first.gate.finishing(first.generation - 1)
    #expect(afterLate.gate.isBusy)
    #expect(!afterLate.isFresh)
}

// MARK: - Кто ответил в замере

private struct PartialRunner: CommandRunning {
    let answers: [String: String]
    let toolExists: Bool
    func run(_ path: String, _ args: [String]) -> String? { answers[path] }
    func isExecutable(_ path: String) -> Bool { toolExists }
}

@Test func failedUtilityIsNotCountedAsAnsweredSource() {
    // Сорвавшаяся утилита неотличима от отключённого устройства по одному лишь
    // отсутствию в списке. Если считать её ответившей, взведение порога
    // забудется и карточка выедет второй раз на том же заряде.
    let runner = PartialRunner(answers: [:], toolExists: false)
    let poll = DevicesProvider.measure(runner: runner)
    #expect(poll.devices.isEmpty)
    #expect(poll.answered.isEmpty)
}

@Test func answeringSourcesAreNamedOneByOne() {
    let runner = PartialRunner(
        answers: ["/usr/bin/pmset": " -InternalBattery-0 (id=1)\t50%; discharging; 1:00 remaining"],
        toolExists: false)
    let poll = DevicesProvider.measure(runner: runner)
    #expect(poll.answered == [.mac])
    #expect(poll.devices.count == 1)
}

@Test func missingPhoneToolMeansWeKnowNothingAboutThePhone() {
    // Утилиты нет — про телефон неизвестно ничего, и забывать его состояние
    // мы не вправе. Она есть, но телефон не подключён — это уже ответ.
    let withoutTool = PartialRunner(answers: [:], toolExists: false)
    #expect(!DevicesProvider.measure(runner: withoutTool).answered.contains(.phone))

    let withTool = PartialRunner(answers: [:], toolExists: true)
    #expect(DevicesProvider.measure(runner: withTool).answered.contains(.phone))
    #expect(DevicesProvider.measure(runner: withTool).devices.isEmpty)
}
