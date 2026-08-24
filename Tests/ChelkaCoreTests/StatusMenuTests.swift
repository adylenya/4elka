import Testing
@testable import ChelkaCore

@Test func menuAlwaysOffersQuitBecauseItIsTheOnlyWayOut() {
    // Иконка в строке меню — единственный способ выключить приложение:
    // иконки в доке нет, панель живёт только над челкой.
    for panel in [PanelState.hidden, .peek, .activity, .expanded] {
        #expect(StatusMenu.items(panel: panel).contains(.quit))
    }
}

@Test func menuOffersToShowPanelOnlyWhenItIsNotAlreadyOpen() {
    #expect(StatusMenu.items(panel: .hidden).contains(.showPanel))
    #expect(!StatusMenu.items(panel: .expanded).contains(.showPanel))
}

@Test func menuOffersToHideThePanelWhileItIsOpen() {
    // Раньше при раскрытой панели меню не предлагало ничего: «Показать панель»
    // прятали, «Скрыть» не добавляли, а клик по челке был отключён. Выходом
    // оставалось только выключить приложение.
    #expect(StatusMenu.items(panel: .expanded).contains(.hidePanel))
    #expect(!StatusMenu.items(panel: .hidden).contains(.hidePanel))
    #expect(StatusMenu.title(for: .hidePanel, launchesAtLogin: false) == "Скрыть панель")
}

@Test func menuAlwaysOffersAWayToChangeThePanelState() {
    // В любом состоянии есть либо «Показать», либо «Скрыть» — но не пустота.
    for panel in PanelState.allCases {
        let items = StatusMenu.items(panel: panel)
        #expect(items.contains(.showPanel) || items.contains(.hidePanel))
    }
}

@Test func menuAlwaysOffersSettingsAndLaunchToggle() {
    let items = StatusMenu.items(panel: .hidden)
    #expect(items.contains(.openSettings))
    #expect(items.contains(.toggleLaunchAtLogin))
}

@Test func launchToggleTitleSaysWhatWillHappen() {
    // Подпись должна говорить о действии, а не о состоянии: иначе непонятно,
    // включено сейчас или это предложение включить.
    #expect(StatusMenu.title(for: .toggleLaunchAtLogin, launchesAtLogin: false)
            == "Запускать при входе")
    #expect(StatusMenu.title(for: .toggleLaunchAtLogin, launchesAtLogin: true)
            == "Не запускать при входе")
}

@Test func quitTitleNamesTheApp() {
    #expect(StatusMenu.title(for: .quit, launchesAtLogin: false) == "Выключить 4elka")
}
