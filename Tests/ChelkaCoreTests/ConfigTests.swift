import Testing
@testable import ChelkaCore

@Test func configHasHistoryQuotas() {
    #expect(Config.History.textLimit == 200)
    #expect(Config.History.imageLimit == 30)
    #expect(Config.History.fileLimit == 50)
}

@Test func configHasBatteryThresholds() {
    #expect(Config.Battery.lowThreshold == 20)
    #expect(Config.Battery.highThreshold == 80)
    #expect(Config.Battery.hysteresis == 5)
}
