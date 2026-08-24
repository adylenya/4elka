import Testing
@testable import ChelkaCore

// Сверять константу с её же литералом бессмысленно: такой тест падает только
// когда кто-то поменял `Config`, и починкой оказывается правка теста. Проверяем
// отношения между константами — то, что действительно обязано выполняться.

@Test func historyQuotasGrowWithHowCheapTheItemIs() {
    // Текста хранится больше всего, картинок меньше всего: картинка занимает
    // мегабайты, строка — байты.
    #expect(Config.History.imageLimit < Config.History.fileLimit)
    #expect(Config.History.fileLimit < Config.History.textLimit)
    #expect(Config.Limits.historyQuota.contains(Config.History.textLimit))
    #expect(Config.Limits.historyQuota.contains(Config.History.imageLimit))
    #expect(Config.Limits.historyQuota.contains(Config.History.fileLimit))
}

@Test func batteryThresholdsLeaveRoomForHysteresis() {
    // Гистерезис обязан быть меньше нижнего порога и меньше расстояния между
    // порогами, иначе уведомление о заряде начнёт дребезжать.
    #expect(Config.Battery.hysteresis < Config.Battery.lowThreshold)
    #expect(Config.Battery.lowThreshold + Config.Battery.hysteresis
            < Config.Battery.highThreshold)
    #expect(Config.Battery.highThreshold < Config.Battery.fullThreshold)
    #expect(Config.Limits.hysteresis.contains(Config.Battery.hysteresis))
}

@Test func cardOutlivesSeveralTicksOfItsOwnTimer() {
    // Таймер, тикающий реже времени жизни карточки, не погасил бы её вовремя.
    #expect(Config.Activity.tickInterval < Config.Activity.duration)
    #expect(Config.Limits.activityDuration.contains(Config.Activity.duration))
}
