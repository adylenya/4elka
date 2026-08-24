import Combine
import Foundation

@MainActor
public final class DevicesProvider: ObservableObject {
    @Published public private(set) var devices: [DeviceCharge] = []

    private let runner: CommandRunning
    private var timer: Timer?
    /// Замок и старшинство опросов. Без него повисшая утилита занимала поток
    /// намертво, а таймер добавлял по такому потоку в минуту.
    private var gate = PollGate()
    /// Наружу уходит весь замер, а не только список: кто из источников ответил,
    /// решает, можно ли забывать взведение порогов.
    public var onUpdate: ((DevicePoll) -> Void)?

    public init(runner: CommandRunning = SystemCommandRunner()) { self.runner = runner }

    public func start() {
        // Повторный запуск не должен заводить второй таймер: два таймера
        // опрашивают устройства вдвое чаще и оба живут до конца процесса.
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Config.Battery.pollInterval,
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func stop() { timer?.invalidate(); timer = nil }

    /// Гасим сами: таймер держит сильную ссылку на цель через свою цель
    /// запуска, и провайдер, о котором забыли, продолжал бы опрашивать
    /// утилиты до конца процесса. `isolated`, потому что таймер не `Sendable`
    /// и трогать его из неизолированного разрушителя Swift 6 не даёт.
    isolated deinit { timer?.invalidate() }

    /// system_profiler занимает 1–2 секунды, поэтому опрос уходит в фон,
    /// а на главный поток возвращается только готовый замер.
    private func refresh() {
        guard let (nextGate, generation) = gate.starting() else { return }
        gate = nextGate
        let runner = self.runner
        DispatchQueue.global(qos: .utility).async {
            let poll = Self.measure(runner: runner)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let (afterFinish, isFresh) = self.gate.finishing(generation)
                self.gate = afterFinish
                // Отставший замер выбрасываем целиком: применить его значило бы
                // перезаписать свежий список устаревшим.
                guard isFresh else { return }
                self.devices = poll.devices
                self.onUpdate?(poll)
            }
        }
    }

    /// Один замер трёх источников. Чистая функция от исполнителя команд —
    /// проверяется тестом на подделке, без похода к настоящим утилитам.
    ///
    /// `nonisolated` обязательно: замер идёт на фоновой очереди, потому что три
    /// утилиты вместе занимают несколько секунд. Изоляция главным актором тут
    /// была бы обещанием, которого код не держит — и компилятор её пропускал,
    /// потому что у очереди из старого интерфейса замыкание не помечено
    /// `Sendable`.
    nonisolated static func measure(runner: CommandRunning) -> DevicePoll {
        var devices: [DeviceCharge] = []
        var answered: Set<DeviceCharge.Source> = []

        if let output = runner.run("/usr/bin/pmset", ["-g", "batt"]) {
            answered.insert(.mac)
            if let mac = MacBatteryParser.parse(output) { devices.append(mac) }
        }
        if let json = runner.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
           let data = json.data(using: .utf8) {
            answered.insert(.bluetooth)
            devices.append(contentsOf: BluetoothParser.parse(data))
        }
        // У айфона «ответил» — это «утилита на месте». Отличить «телефон не
        // подключён» от «утилита сорвалась» по её выходу нельзя: она в обоих
        // случаях возвращает ненулевой код. Зато если утилиты нет вовсе, мы
        // про телефон не знаем ничего и забывать его состояние не вправе.
        if runner.isExecutable(PhoneBattery.toolPath) {
            answered.insert(.phone)
            if let phone = PhoneBattery.read(runner: runner) { devices.append(phone) }
        }
        return DevicePoll(devices: devices, answered: answered)
    }
}
