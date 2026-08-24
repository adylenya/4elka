import Foundation

/// Кто из опросов устройств сейчас главный.
///
/// Два правила, и нужны оба.
///
/// **Замок.** Пока опрос идёт, следующий тик таймера не начинает второй.
/// Без замка повисшая утилита (`ideviceinfo` на заблокированном айфоне,
/// не доверяющем машине) занимала поток намертво, а таймер добавлял по такому
/// потоку в минуту — через час шестьдесят мёртвых потоков, и всё, что ходит
/// на общую очередь, перестаёт получать исполнителя.
///
/// **Старшинство.** Результат опроса, начатого раньше уже применённого,
/// отбрасывается: иначе медленный опрос, доехавший последним, перезаписал бы
/// свежий список устаревшим.
///
/// Иммутабельна: каждое изменение возвращает новый экземпляр. Правила проверяются
/// тестом на чистом типе, а не глазами по гонке в провайдере.
struct PollGate: Equatable, Sendable {
    private let started: Int
    private let applied: Int
    private let isRunning: Bool

    init() {
        started = 0
        applied = 0
        isRunning = false
    }

    private init(started: Int, applied: Int, isRunning: Bool) {
        self.started = started
        self.applied = applied
        self.isRunning = isRunning
    }

    var isBusy: Bool { isRunning }

    /// `nil` — опрос уже идёт, наложение не допускаем.
    func starting() -> (gate: PollGate, generation: Int)? {
        guard !isRunning else { return nil }
        let generation = started + 1
        return (PollGate(started: generation, applied: applied, isRunning: true), generation)
    }

    /// Пришёл результат. `isFresh` — применять ли его.
    ///
    /// Замок снимает только тот опрос, который начинали последним: результат
    /// отставшего не должен открывать дорогу второму опросу поверх идущего.
    func finishing(_ generation: Int) -> (gate: PollGate, isFresh: Bool) {
        let isFresh = generation > applied
        return (PollGate(started: started,
                         applied: max(applied, generation),
                         isRunning: isRunning && generation != started),
                isFresh)
    }
}
