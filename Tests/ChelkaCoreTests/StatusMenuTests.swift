import Testing
@testable import ChelkaCore

@Test func menuAlwaysOffersQuitBecauseItIsTheOnlyWayOut() {
    // Иконка в строке меню — единственный способ выключить приложение:
    // иконки в доке нет, панель живёт только над челкой.
    for panel in [PanelState.hidden, .peek, .activity, .expanded] {
        #expect(StatusMenu.items(panel: panel, launchesAtLogin: false).contains(.quit))
    }
}

@Test func menuOffersToShowPanelOnlyWhenItIsNotAlreadyOpen() {
    #expect(StatusMenu.items(panel: .hidden, launchesAtLogin: false).contains(.showPanel))
    #expect(!StatusMenu.items(panel: .expanded, launchesAtLogin: false).contains(.showPanel))
}

@Test func menuAlwaysOffersSettingsAndLaunchToggle() {
    let items = StatusMenu.items(panel: .hidden, launchesAtLogin: false)
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
