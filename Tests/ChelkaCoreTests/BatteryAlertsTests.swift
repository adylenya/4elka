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

@Test func fullChargeSuppressesTheRedundantHighAlert() {
    // Устройство, впервые увиденное сразу на сотне при зарядке, не должно выдать
    // две карточки об одном событии.
    let alerts = BatteryAlerts()
    let (_, fired) = alerts.evaluating([dev("Айфон", 100, charging: true)])
    #expect(fired.count == 1)
    #expect(fired.first?.level == .full)
}

@Test func rearmsExactlyAtTheHysteresisBoundary() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating([dev("Наушники", 30)])
    (alerts, _) = alerts.evaluating([dev("Наушники", 19)])
    // 20 + 5 = 25 ровно: граница включительная, значит взводится.
    (alerts, _) = alerts.evaluating([dev("Наушники", 25)])
    (alerts, fired) = alerts.evaluating([dev("Наушники", 19)])
    #expect(fired.count == 1)
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
    let alerts = BatteryAlerts()
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

// MARK: - Пороги из настроек

/// Раздел «Заряд» в окне настроек обязан что-то менять. Раньше правила брали
/// пороги прямо из `Config`, и три крутилки в настройках только сохранялись в
/// файл, ни на что не влияя.
@Test func thresholdsFromSettingsDecideWhenTheCardComesOut() {
    var settings = Settings.defaults
    settings.batteryLow = 50
    let alerts = BatteryAlerts()
    // Сорок процентов при пороге по умолчанию (20) — ещё не повод.
    #expect(alerts.evaluating([dev("Наушники", 40)]).1.isEmpty)
    // При пороге 50 из настроек — уже повод.
    let fired = alerts.evaluating([dev("Наушники", 40)],
                                  thresholds: settings.batteryThresholds).1
    #expect(fired.count == 1)
    #expect(fired.first?.level == .low)
}

/// Гистерезис из настроек решает, когда правило взводится заново: с большим
/// зазором тот же дребезг заряда не даёт второй карточки.
@Test func hysteresisFromSettingsDecidesWhenTheRuleRearms() {
    var settings = Settings.defaults
    settings.batteryLow = 20
    settings.batteryHysteresis = 20
    let thresholds = settings.batteryThresholds
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, fired) = alerts.evaluating([dev("Наушники", 19)], thresholds: thresholds)
    #expect(fired.count == 1)
    // 35 < 20 + 20 — правило ещё не взведено, значит второй карточки не будет.
    (alerts, _) = alerts.evaluating([dev("Наушники", 35)], thresholds: thresholds)
    (_, fired) = alerts.evaluating([dev("Наушники", 19)], thresholds: thresholds)
    #expect(fired.isEmpty)
}
