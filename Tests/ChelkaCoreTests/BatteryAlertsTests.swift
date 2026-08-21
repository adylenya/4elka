import Testing
@testable import ChelkaCore

private func dev(_ name: String, _ percent: Int, charging: Bool = false) -> DeviceCharge {
    DeviceCharge(name: name, percent: percent, isCharging: charging,
                 source: .bluetooth, symbol: "airpods")
}

@Test func firesOnceWhenCrossingLowThreshold() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, fired) = alerts.evaluating([dev("Наушники", 25)])
    #expect(fired.isEmpty)
    (alerts, fired) = alerts.evaluating([dev("Наушники", 19)])
    #expect(fired.count == 1)
    #expect(fired.first?.level == .low)
}

@Test func doesNotRepeatWhileStayingBelowThreshold() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating([dev("Наушники", 25)])
    (alerts, _) = alerts.evaluating([dev("Наушники", 19)])
    for percent in [18, 17, 12, 5, 1] {
        (alerts, fired) = alerts.evaluating([dev("Наушники", percent)])
        #expect(fired.isEmpty)
    }
}

@Test func rearmsOnlyAfterRisingAboveHysteresis() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating([dev("Наушники", 25)])
    (alerts, _) = alerts.evaluating([dev("Наушники", 19)])
    // 20 + 5 = 25 — ещё не перевзвелось.
    (alerts, _) = alerts.evaluating([dev("Наушники", 24)])
    (alerts, fired) = alerts.evaluating([dev("Наушники", 19)])
    #expect(fired.isEmpty)
    // Поднялось выше 25 — взвелось заново.
    (alerts, _) = alerts.evaluating([dev("Наушники", 30)])
    (alerts, fired) = alerts.evaluating([dev("Наушники", 19)])
    #expect(fired.count == 1)
}

@Test func highThresholdFiresOnlyWhileCharging() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating([dev("Айфон", 70, charging: false)])
    (alerts, fired) = alerts.evaluating([dev("Айфон", 85, charging: false)])
    #expect(fired.isEmpty)

    var charging = BatteryAlerts()
    (charging, _) = charging.evaluating([dev("Айфон", 70, charging: true)])
    (charging, fired) = charging.evaluating([dev("Айфон", 85, charging: true)])
    #expect(fired.first?.level == .high)
}

@Test func fullChargeFiresItsOwnAlert() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating([dev("Айфон", 95, charging: true)])
    (alerts, fired) = alerts.evaluating([dev("Айфон", 100, charging: true)])
    #expect(fired.contains { $0.level == .full })
}

@Test func forgetsDeviceThatDisappeared() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating([dev("Наушники", 25)])
    (alerts, _) = alerts.evaluating([dev("Наушники", 19)])
    // Наушники выключили — состояние забылось.
    (alerts, _) = alerts.evaluating([])
    // Включили обратно тоже на 19 — правило должно отработать заново.
    (alerts, fired) = alerts.evaluating([dev("Наушники", 19)])
    #expect(fired.count == 1)
}

@Test func firstSightBelowThresholdFiresImmediately() {
    var alerts = BatteryAlerts()
    let (_, fired) = alerts.evaluating([dev("Наушники", 8)])
    #expect(fired.count == 1)
    #expect(fired.first?.level == .low)
}

@Test func handlesSeveralDevicesIndependently() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating([dev("Наушники", 50), dev("Мышь", 50)])
    (alerts, fired) = alerts.evaluating([dev("Наушники", 10), dev("Мышь", 50)])
    #expect(fired.count == 1)
    #expect(fired.first?.deviceName == "Наушники")
}

@Test func alertEventUsesBatteryPriority() {
    let alert = BatteryAlert(deviceName: "Наушники", percent: 12, level: .low)
    #expect(alert.activityEvent.kind == .battery)
    #expect(alert.activityEvent.title.contains("Наушники"))
}
