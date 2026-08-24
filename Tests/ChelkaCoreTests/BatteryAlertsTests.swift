import Testing
@testable import ChelkaCore

private func dev(_ name: String, _ percent: Int, charging: Bool = false) -> DeviceCharge {
    DeviceCharge(name: name, percent: percent, isCharging: charging,
                 source: .bluetooth, symbol: "airpods")
}

private func mac(_ percent: Int, charging: Bool = false) -> DeviceCharge {
    DeviceCharge(name: "Мак", percent: percent, isCharging: charging,
                 source: .mac, symbol: "laptopcomputer")
}

/// Удачный опрос: все источники ответили. Именно про такой опрос можно сказать,
/// что отсутствующее устройство действительно отключили.
private func polled(_ devices: DeviceCharge...) -> DevicePoll { .complete(devices) }

@Test func firesOnceWhenCrossingLowThreshold() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, fired) = alerts.evaluating(polled(dev("Наушники", 25)))
    #expect(fired.isEmpty)
    (alerts, fired) = alerts.evaluating(polled(dev("Наушники", 19)))
    #expect(fired.count == 1)
    #expect(fired.first?.level == .low)
}

@Test func doesNotRepeatWhileStayingBelowThreshold() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 25)))
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 19)))
    for percent in [18, 17, 12, 5, 1] {
        (alerts, fired) = alerts.evaluating(polled(dev("Наушники", percent)))
        #expect(fired.isEmpty)
    }
}

@Test func rearmsOnlyAfterRisingAboveHysteresis() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 25)))
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 19)))
    // 20 + 5 = 25 — ещё не перевзвелось.
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 24)))
    (alerts, fired) = alerts.evaluating(polled(dev("Наушники", 19)))
    #expect(fired.isEmpty)
    // Поднялось выше 25 — взвелось заново.
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 30)))
    (alerts, fired) = alerts.evaluating(polled(dev("Наушники", 19)))
    #expect(fired.count == 1)
}

@Test func highThresholdFiresOnlyWhileCharging() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating(polled(dev("Айфон", 70, charging: false)))
    (alerts, fired) = alerts.evaluating(polled(dev("Айфон", 85, charging: false)))
    #expect(fired.isEmpty)

    var charging = BatteryAlerts()
    (charging, _) = charging.evaluating(polled(dev("Айфон", 70, charging: true)))
    (charging, fired) = charging.evaluating(polled(dev("Айфон", 85, charging: true)))
    #expect(fired.first?.level == .high)
}

@Test func fullChargeSuppressesTheRedundantHighAlert() {
    // Устройство, впервые увиденное сразу на сотне при зарядке, не должно выдать
    // две карточки об одном событии.
    let alerts = BatteryAlerts()
    let (_, fired) = alerts.evaluating(polled(dev("Айфон", 100, charging: true)))
    #expect(fired.count == 1)
    #expect(fired.first?.level == .full)
}

@Test func rearmsExactlyAtTheHysteresisBoundary() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 30)))
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 19)))
    // 20 + 5 = 25 ровно: граница включительная, значит взводится.
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 25)))
    (alerts, fired) = alerts.evaluating(polled(dev("Наушники", 19)))
    #expect(fired.count == 1)
}

@Test func fullChargeFiresItsOwnAlert() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating(polled(dev("Айфон", 95, charging: true)))
    (alerts, fired) = alerts.evaluating(polled(dev("Айфон", 100, charging: true)))
    #expect(fired.contains { $0.level == .full })
}

/// «Заряжен, отключай» без кабеля — совет отключить то, что и так отключено.
/// Так выглядит каждый холодный старт на полной батарее и каждое возвращение
/// к маку, снятому с сети на сотне.
@Test func fullAlertDoesNotFireWithoutCable() {
    let alerts = BatteryAlerts()
    let (_, fired) = alerts.evaluating(polled(dev("Мак", 100, charging: false)))
    #expect(fired.isEmpty)
}

/// И не залипает: кабель воткнули — карточка приходит.
@Test func fullAlertFiresOnceTheCableIsBack() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating(polled(dev("Мак", 100, charging: false)))
    (alerts, fired) = alerts.evaluating(polled(dev("Мак", 100, charging: true)))
    #expect(fired.first?.level == .full)
}

// MARK: - Забывать состояние можно только по удачному опросу

/// Требование: устройство забывается тогда, когда его источник ОТВЕТИЛ, а
/// устройства в ответе не оказалось. Тогда наушники действительно выключили,
/// и при следующем включении правило порога обязано отработать заново.
@Test func forgetsDeviceThatASuccessfulPollDidNotSee() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 25)))
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 19)))
    // Блютус ответил, наушников в ответе нет — их выключили.
    (alerts, _) = alerts.evaluating(DevicePoll(devices: [], answered: [.bluetooth]))
    // Включили обратно тоже на 19 — правило отрабатывает заново.
    (alerts, fired) = alerts.evaluating(polled(dev("Наушники", 19)))
    #expect(fired.count == 1)
}

/// Требование: сорвавшийся опрос состояние НЕ стирает. Мак на 15%, карточка
/// показана; следующий опрос — `pmset` вернул ненулевой код, мака в списке нет;
/// третий опрос — мак снова на 15%. Карточка обязана остаться одной: заряд
/// тот же, событие то же.
@Test func failedPollDoesNotRepeatTheAlertOnTheSameCharge() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    var total = 0
    (alerts, fired) = alerts.evaluating(DevicePoll(devices: [mac(15)], answered: [.mac]))
    total += fired.count
    // pmset сорвался: устройства в опросе нет, но и ответа от источника нет.
    (alerts, fired) = alerts.evaluating(DevicePoll.failed)
    total += fired.count
    // Тот же мак, тот же заряд.
    (alerts, fired) = alerts.evaluating(DevicePoll(devices: [mac(15)], answered: [.mac]))
    total += fired.count
    #expect(total == 1)
}

/// Провал одного источника не имеет права стирать состояние устройств другого,
/// и наоборот: удачный ответ блютуса про отключённые наушники — забывает
/// наушники, но не мака, про которого в этом опросе ничего не сказали.
@Test func sourcesAreForgottenIndependently() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating(DevicePoll(devices: [mac(15), dev("Наушники", 15)],
                                               answered: [.mac, .bluetooth]))
    // Блютус ответил без наушников (их выключили), pmset сорвался.
    (alerts, _) = alerts.evaluating(DevicePoll(devices: [], answered: [.bluetooth]))
    // Наушники вернулись на том же заряде — карточка положена заново.
    (alerts, fired) = alerts.evaluating(DevicePoll(devices: [dev("Наушники", 15)],
                                                   answered: [.bluetooth]))
    #expect(fired.count == 1)
    // А мак на том же заряде — нет: про него ничего не забывали.
    (alerts, fired) = alerts.evaluating(DevicePoll(devices: [mac(15)], answered: [.mac]))
    #expect(fired.isEmpty)
}

@Test func firstSightBelowThresholdFiresImmediately() {
    let alerts = BatteryAlerts()
    let (_, fired) = alerts.evaluating(polled(dev("Наушники", 8)))
    #expect(fired.count == 1)
    #expect(fired.first?.level == .low)
}

@Test func handlesSeveralDevicesIndependently() {
    var alerts = BatteryAlerts()
    var fired: [BatteryAlert]
    (alerts, _) = alerts.evaluating(polled(dev("Наушники", 50), dev("Мышь", 50)))
    (alerts, fired) = alerts.evaluating(polled(dev("Наушники", 10), dev("Мышь", 50)))
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
    #expect(alerts.evaluating(.complete([dev("Наушники", 40)])).1.isEmpty)
    // При пороге 50 из настроек — уже повод.
    let fired = alerts.evaluating(.complete([dev("Наушники", 40)]),
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
    (alerts, fired) = alerts.evaluating(.complete([dev("Наушники", 19)]), thresholds: thresholds)
    #expect(fired.count == 1)
    // 35 < 20 + 20 — правило ещё не взведено, значит второй карточки не будет.
    (alerts, _) = alerts.evaluating(.complete([dev("Наушники", 35)]), thresholds: thresholds)
    (_, fired) = alerts.evaluating(.complete([dev("Наушники", 19)]), thresholds: thresholds)
    #expect(fired.isEmpty)
}
