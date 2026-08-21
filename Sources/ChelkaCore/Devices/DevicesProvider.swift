import Combine
import Foundation

@MainActor
public final class DevicesProvider: ObservableObject {
    @Published public private(set) var devices: [DeviceCharge] = []

    private let runner: CommandRunning
    private var timer: Timer?
    public var onUpdate: (([DeviceCharge], [DeviceCharge]) -> Void)?

    public init(runner: CommandRunning = SystemCommandRunner()) { self.runner = runner }

    public func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Config.Battery.pollInterval,
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func stop() { timer?.invalidate(); timer = nil }

    /// system_profiler занимает 1–2 секунды, поэтому опрос уходит в фон,
    /// а на главный поток возвращается только готовый список.
    private func refresh() {
        let runner = self.runner
        DispatchQueue.global(qos: .utility).async {
            var next: [DeviceCharge] = []
            if let output = runner.run("/usr/bin/pmset", ["-g", "batt"]),
               let mac = MacBatteryParser.parse(output) { next.append(mac) }
            if let json = runner.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
               let data = json.data(using: .utf8) { next.append(contentsOf: BluetoothParser.parse(data)) }
            if let phone = PhoneBattery.read(runner: runner) { next.append(phone) }

            Task { @MainActor [weak self] in
                guard let self else { return }
                let previous = self.devices
                self.devices = next
                self.onUpdate?(previous, next)
            }
        }
    }
}
