import Testing
import AppKit
@testable import ChelkaCore

private let measured = NotchGeometry(
    rect: CGRect(x: 918, y: 1291, width: 220, height: 38), hasPhysicalNotch: true)

private let everyState: [PanelState] = [.hidden, .peek, .activity, .expanded]

private func card(_ kind: ActivityEvent.Kind = .clipboard) -> ActivityEvent {
    ActivityEvent(kind: kind, title: "скопировано")
}

// MARK: - Представление: чистое значение от пары (состояние, очередь)

@Test func hiddenPanelIsNotOnScreenAtAll() {
    let p = PanelPresentation.make(state: .hidden, event: nil, geometry: measured)
    #expect(!p.isVisible)
    #expect(p.frame == nil)
    #expect(!p.takesKeyboard)
}

@Test func onlyExpandedTakesTheKeyboard() {
    for state in everyState {
        let p = PanelPresentation.make(state: state, event: nil, geometry: measured)
        #expect(p.takesKeyboard == (state == .expanded))
        #expect(p.allowsKeyboard == (state == .expanded))
    }
}

@Test func cardIsDrawnOnlyWhenThereIsSomethingInTheQueue() {
    // Находка 2: рисование карточки — функция пары (состояние, очередь).
    // Состояние «карточка» с пустой очередью не имеет права рисовать карточку.
    let withEvent = PanelPresentation.make(state: .activity, event: card(), geometry: measured)
    #expect(withEvent.content.kind == .activity)
    let empty = PanelPresentation.make(state: .activity, event: nil, geometry: measured)
    #expect(empty.content.kind != .activity)
}

@Test func expandedPanelKeepsItsHistoryEvenWhileACardIsStillInFlight() {
    // Ровно тот тупик, из которого не было выхода: карточка уже летела, человек
    // выбрал «Показать панель», и следующий тик таймера подменял сетку истории
    // чёрной фигурой карточки — навсегда.
    let p = PanelPresentation.make(state: .expanded, event: card(), geometry: measured)
    #expect(p.content.kind == .expanded)
    #expect(p.content.eventID == nil)
}

@Test func cardContentIsIdentifiedByItsEventSoTicksDoNotRebuildIt() {
    // Находка 6: таймер тикает четыре раза в секунду. Пока событие то же,
    // содержимое обязано считаться тем же — иначе дерево вью пересобирается
    // и картинка перечитывается с диска двенадцать раз за жизнь карточки.
    let event = card()
    let first = PanelPresentation.make(state: .activity, event: event, geometry: measured)
    let second = PanelPresentation.make(state: .activity, event: event, geometry: measured)
    #expect(first.content == second.content)
    let other = PanelPresentation.make(state: .activity, event: card(.battery), geometry: measured)
    #expect(other.content != first.content)
}

@Test func triggerZoneKeepsTakingTheMouseEvenWhenThePanelIsExpanded() {
    // Находка 7: отключение зоны в раскрытом состоянии убирало единственный
    // источник клика — из раскрытой панели нельзя было выйти вовсе.
    for state in everyState {
        let p = PanelPresentation.make(state: state, event: nil, geometry: measured)
        #expect(p.triggerIsInteractive)
    }
}

@Test func withoutAnyScreenTheTriggerZoneStopsEatingClicks() {
    // Иначе невидимое окно, съедающее нажатия, стоит где-то в строке меню.
    for state in everyState {
        let p = PanelPresentation.make(state: state, event: nil, geometry: .none)
        #expect(!p.triggerIsInteractive)
        #expect(!p.isVisible)
    }
}

@Test func everyStatePinnedToTheTopDrawsTheNotchFigure() {
    // Находка 5: раскрытая панель заливала верхние 38 точек стеклом, и челка
    // читалась как чёрный укус. Полосу высотой челки рисует каждое видимое
    // состояние, стекло достаётся только содержимому ниже.
    for state in everyState {
        let p = PanelPresentation.make(state: state, event: card(), geometry: measured)
        #expect(p.drawsNotchFigure == p.isVisible)
    }
}

// MARK: - Применение представления к окнам

@MainActor
private final class FakePanel: PanelSurface {
    var placed: CGRect?
    var visible = false
    var keyboardAllowed = false
    var tookKeyboard = 0
    var presentedContents = 0

    func place(at frame: CGRect) { placed = frame }
    func show() { visible = true }
    func hide() { visible = false }
    func allowKeyboard(_ allowed: Bool) { keyboardAllowed = allowed }
    func takeKeyboard() { tookKeyboard += 1 }
    func present(_ content: NSView) { presentedContents += 1 }
}

@MainActor
private final class FakeTrigger: TriggerSurface {
    var interactive = true
    var movedTo: CGRect?

    func setInteractive(_ enabled: Bool) { interactive = enabled }
    func move(to rect: CGRect) { movedTo = rect }
}

/// Содержимое в тестах не строим: важно, сколько раз его запросили.
@MainActor
private func makePresenter() -> (PanelPresenter, FakePanel, FakeTrigger) {
    let panel = FakePanel()
    let trigger = FakeTrigger()
    let presenter = PanelPresenter(panel: panel, trigger: trigger,
                                   content: { _ in NSView() })
    return (presenter, panel, trigger)
}

@MainActor
@Test func presenterHidesThePanelOnLaunchInsteadOfShowingIt() {
    // Находка 9: окно поднималось на передний план при скрытом состоянии, и
    // применение состояния на запуске не звалось ни разу.
    let (presenter, panel, _) = makePresenter()
    presenter.apply(PanelPresentation.make(state: .hidden, event: nil, geometry: measured))
    #expect(!panel.visible)
    #expect(panel.tookKeyboard == 0)
}

@MainActor
@Test func presenterPlacesThePanelByTheComputedFrame() {
    let (presenter, panel, _) = makePresenter()
    presenter.apply(PanelPresentation.make(state: .peek, event: nil, geometry: measured))
    #expect(panel.visible)
    #expect(panel.placed == PanelFrames.frame(for: .peek, geometry: measured))
}

@MainActor
@Test func presenterRebuildsContentOnlyWhenItActuallyChanges() {
    // Пересборка на каждый вызов обнуляла бы строку поиска и выделение, а
    // на каждый тик таймера — перечитывала бы картинку карточки с диска.
    let (presenter, panel, _) = makePresenter()
    let event = card()
    for _ in 0..<12 {
        presenter.apply(PanelPresentation.make(state: .activity, event: event,
                                               geometry: measured))
    }
    #expect(panel.presentedContents == 1)
    presenter.apply(PanelPresentation.make(state: .expanded, event: event, geometry: measured))
    #expect(panel.presentedContents == 2)
}

@MainActor
@Test func reopeningTheExpandedPanelBuildsItsContentAgain() {
    // Календарь сбрасывается на текущий месяц именно этим: содержимое
    // раскрытой панели собирается заново на каждое раскрытие. Если бы
    // предъявитель признал его прежним, панель открывалась бы на том месяце,
    // куда в прошлый раз ушли стрелками, — а правило обратное.
    let panel = FakePanel()
    var built: [PanelContent.Kind] = []
    let presenter = PanelPresenter(panel: panel, trigger: nil, content: { content in
        built.append(content.kind)
        return NSView()
    })
    presenter.apply(PanelPresentation.make(state: .expanded, event: nil, geometry: measured))
    presenter.apply(PanelPresentation.make(state: .hidden, event: nil, geometry: measured))
    presenter.apply(PanelPresentation.make(state: .expanded, event: nil, geometry: measured))
    #expect(built.filter { $0 == .expanded }.count == 2)
}

@MainActor
@Test func presenterGivesTheKeyboardOnlyToTheExpandedPanel() {
    let (presenter, panel, _) = makePresenter()
    presenter.apply(PanelPresentation.make(state: .activity, event: card(), geometry: measured))
    #expect(!panel.keyboardAllowed)
    #expect(panel.tookKeyboard == 0)
    presenter.apply(PanelPresentation.make(state: .expanded, event: nil, geometry: measured))
    #expect(panel.keyboardAllowed)
    #expect(panel.tookKeyboard == 1)
}

@MainActor
@Test func presenterMovesBothWindowsWhenTheScreenChanges() {
    // Находка 3: смена масштаба в мониторах оставляла панель и невидимую зону
    // на старых координатах — наведение не работало, а окно, съедающее клики,
    // стояло где-то в строке меню.
    let (presenter, panel, trigger) = makePresenter()
    presenter.apply(PanelPresentation.make(state: .peek, event: nil, geometry: measured))
    let moved = NotchGeometry(rect: CGRect(x: 500, y: 700, width: 180, height: 32),
                              hasPhysicalNotch: true)
    presenter.apply(PanelPresentation.make(state: .peek, event: nil, geometry: moved))
    #expect(trigger.movedTo == moved.rect)
    #expect(panel.placed == PanelFrames.frame(for: .peek, geometry: moved))
}

@MainActor
@Test func presenterStopsTheTriggerZoneWhenThereIsNoScreen() {
    let (presenter, panel, trigger) = makePresenter()
    presenter.apply(PanelPresentation.make(state: .peek, event: nil, geometry: .none))
    #expect(!trigger.interactive)
    #expect(!panel.visible)
}

// MARK: - Выбор экрана

@Test func screenChoicePrefersTheMainOneAndFallsBackToTheFirstAvailable() {
    // Находка 8: ранний выход при отсутствии главного экрана бросал весь
    // запуск — приложение оставалось без единого элемента интерфейса.
    #expect(ScreenChoice.chosen(main: 1, all: [2, 3]) == 1)
    #expect(ScreenChoice.chosen(main: nil, all: [2, 3]) == 2)
    #expect(ScreenChoice.chosen(main: Int?.none, all: []) == nil)
}

@MainActor
@Test func screenWatcherFiresOnScreenParameterChanges() {
    var fired = 0
    let watcher = ScreenWatcher { fired += 1 }
    NotificationCenter.default.post(
        name: NSApplication.didChangeScreenParametersNotification, object: nil)
    #expect(fired == 1)
    watcher.stop()
    NotificationCenter.default.post(
        name: NSApplication.didChangeScreenParametersNotification, object: nil)
    #expect(fired == 1)
}
