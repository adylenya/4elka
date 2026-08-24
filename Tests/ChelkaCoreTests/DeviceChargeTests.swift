import Testing
import Foundation
@testable import ChelkaCore

private func fixture(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: ext))
    return try Data(contentsOf: url)
}

@Test func parsesAirPodsFromRealBluetoothDump() throws {
    let devices = BluetoothParser.parse(try fixture("bluetooth", "json"))
    let airpods = try #require(devices.first { $0.name.contains("AirPods") })
    // Показываем минимум из двух ушей, чтобы не соврать в плюс.
    #expect(airpods.percent == 51)
    #expect(airpods.source == .bluetooth)
}

@Test func bluetoothParserSurvivesGarbage() {
    #expect(BluetoothParser.parse(Data("не json".utf8)).isEmpty)
    #expect(BluetoothParser.parse(Data()).isEmpty)
}

@Test func bluetoothParserTakesSingleLevelWhenDeviceHasOne() {
    let json = """
    {"SPBluetoothDataType":[{"device_connected":[{"Magic Mouse":{"device_batteryLevelMain":"77%"}}]}]}
    """
    let devices = BluetoothParser.parse(Data(json.utf8))
    #expect(devices.count == 1)
    #expect(devices.first?.percent == 77)
}

@Test func bluetoothParserSkipsDevicesWithoutBattery() {
    let json = """
    {"SPBluetoothDataType":[{"device_connected":[{"Колонка":{"device_minorType":"Speaker"}}]}]}
    """
    #expect(BluetoothParser.parse(Data(json.utf8)).isEmpty)
}

@Test func parsesMacBatteryFromRealPmsetOutput() throws {
    let text = String(data: try fixture("pmset-batt", "txt"), encoding: .utf8)!
    let mac = try #require(MacBatteryParser.parse(text))
    #expect(mac.percent == 100)
    #expect(mac.source == .mac)
    // В фикстуре состояние «charged» — оно обязано читаться как «на зарядке»,
    // иначе следующая задача пришлёт «заряд на исходе» на полной батарее.
    #expect(mac.isCharging)
}

@Test func macBatteryDetectsCharging() {
    let text = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=1)\t64%; charging; 1:12 remaining present: true
    """
    let mac = try! #require(MacBatteryParser.parse(text))
    #expect(mac.percent == 64)
    #expect(mac.isCharging)
}

@Test func macBatteryDetectsDischarging() {
    let text = """
    Now drawing from 'Battery Power'
     -InternalBattery-0 (id=1)\t42%; discharging; 2:03 remaining present: true
    """
    let mac = try! #require(MacBatteryParser.parse(text))
    #expect(mac.percent == 42)
    #expect(!mac.isCharging)
}

@Test func macBatteryReturnsNilForDesktopWithoutBattery() {
    #expect(MacBatteryParser.parse("Now drawing from 'AC Power'") == nil)
}

/// Строка снята с целевой машины в момент, когда воткнули зарядку: вместо
/// времени в поле остатка приходит `(no estimate)` — скобки и слова, а не
/// `H:MM remaining`. Разбор не имеет права об это спотыкаться.
@Test func macBatteryParsesRealChargingLineWithoutTimeEstimate() throws {
    let text = String(data: try fixture("pmset-charging", "txt"), encoding: .utf8)!
    let mac = try #require(MacBatteryParser.parse(text))
    #expect(mac.percent == 86)
    #expect(mac.isCharging)
}

/// Та же машина на батарее.
@Test func macBatteryParsesRealDischargingLine() throws {
    let text = String(data: try fixture("pmset-discharging", "txt"), encoding: .utf8)!
    let mac = try #require(MacBatteryParser.parse(text))
    #expect(mac.percent == 88)
    #expect(!mac.isCharging)
}

/// Оптимизированная зарядка держит батарею на 80% и печатает `not charging`.
/// Это НЕ зарядка: система сама остановила ток, отключать нечего. Строка
/// содержит слово `charging` и не содержит `discharging` — на подстроке по
/// всей строке разбор врал ровно тут.
@Test func macBatteryOptimizedChargingIsNotCharging() throws {
    let text = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=10000001)\t80%; not charging present: true
    """
    let mac = try #require(MacBatteryParser.parse(text))
    #expect(mac.percent == 80)
    #expect(!mac.isCharging)
}

/// То же самое, но с полем `AC attached` перед состоянием: кабель есть,
/// а ток не идёт.
@Test func macBatteryAcAttachedWithoutChargingIsNotCharging() throws {
    let text = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=10000001)\t80%; AC attached; not charging present: true
    """
    let mac = try #require(MacBatteryParser.parse(text))
    #expect(mac.percent == 80)
    #expect(!mac.isCharging)
}

/// Последние проценты система доливает медленно и называет это отдельно.
@Test func macBatteryFinishingChargeIsCharging() throws {
    let text = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=10000001)\t99%; finishing charge; 0:05 remaining present: true
    """
    #expect(try #require(MacBatteryParser.parse(text)).isCharging)
}

/// Один `AC attached` без состояния зарядки — обещать «можно отключать» нельзя.
@Test func macBatteryAcAttachedAloneIsNotCharging() throws {
    let text = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=10000001)\t50%; AC attached; present: true
    """
    #expect(try !#require(MacBatteryParser.parse(text)).isCharging)
}

/// Все формулировки состояния, какие печатает pmset, перечислены явно.
/// Незнакомое слово — не зарядка: врать в сторону «можно отключать» дороже,
/// чем промолчать.
@Test func macBatteryReadsUnknownStateAsNotCharging() throws {
    let text = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=10000001)\t50%; неизвестно что; present: true
    """
    let mac = try #require(MacBatteryParser.parse(text))
    #expect(mac.percent == 50)
    #expect(!mac.isCharging)
}

private struct StubRunner: CommandRunning {
    let outputs: [String: String?]
    func run(_ path: String, _ args: [String]) -> String? { outputs[args.last ?? ""] ?? nil }
}

@Test func readsPhoneBatteryWhenToolAndDevicePresent() {
    let runner = StubRunner(outputs: ["BatteryCurrentCapacity": "63",
                                      "BatteryIsCharging": "true",
                                      "DeviceName": "Arseniy"])
    let phone = try! #require(PhoneBattery.read(runner: runner))
    #expect(phone.percent == 63)
    #expect(phone.isCharging)
    #expect(phone.name == "Arseniy")
    #expect(phone.source == .phone)
}

@Test func phoneBatteryIsNilWhenCableUnplugged() {
    // Без кабеля утилита не отдаёт ничего — строка айфона просто исчезает.
    #expect(PhoneBattery.read(runner: StubRunner(outputs: [:])) == nil)
}

@Test func phoneBatteryIsNilOnNonNumericOutput() {
    #expect(PhoneBattery.read(runner: StubRunner(outputs: ["BatteryCurrentCapacity": "ERROR"])) == nil)
}
