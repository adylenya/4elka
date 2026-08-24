import Testing
import AppKit
@testable import ChelkaCore

/// Замеренная челка целевой машины: MacBook Pro 16″ M1 Pro, 2056×1329 точек.
private let measured = NotchGeometry(
    rect: CGRect(x: 918, y: 1291, width: 220, height: 38), hasPhysicalNotch: true)

/// Экран без физического выреза: запасная плашка по центру верхнего края.
private let plain = NotchGeometry(
    rect: CGRect(x: 850, y: 1016, width: 220, height: 32), hasPhysicalNotch: false)

private let everyState: [PanelState] = [.hidden, .peek, .activity, .expanded]

// MARK: - Рамка есть у каждого состояния, и считает её одна функция

@Test func hiddenStateHasNoFrameAtAll() {
    // Скрытая панель не «сжимается в полоску», а уходит с экрана совсем.
    #expect(PanelFrames.frame(for: .hidden, geometry: measured) == nil)
    #expect(PanelFrames.contentSize(for: .hidden, geometry: measured) == nil)
}

@Test func everyVisibleStateIsPinnedToTheTopOfTheScreenAndCentredOnTheNotch() {
    // Фигура продолжает челку, а не висит под ней — это верно для всех
    // состояний, а не только для карточки.
    for state in everyState where state != .hidden {
        guard let frame = PanelFrames.frame(for: state, geometry: measured) else {
            Issue.record("у состояния \(state) нет рамки")
            continue
        }
        #expect(frame.maxY == measured.rect.maxY)
        #expect(frame.midX == measured.rect.midX)
    }
}

@Test func everyVisibleStateKeepsWingsBesideTheNotch() {
    // Крылья слева и справа обязаны быть у всех состояний: без них фигура
    // не расширяет челку, и та остаётся заметной.
    for state in everyState where state != .hidden {
        guard let frame = PanelFrames.frame(for: state, geometry: measured) else { continue }
        let wing = (frame.width - measured.rect.width) / 2
        #expect(wing >= Config.Notch.wingWidth)
    }
}

@Test func everyVisibleStateLeavesRoomForItsContentBelowTheNotch() {
    // Главное расхождение находки 4: раскладка считает тело ниже челки, а
    // размер окна раньше приходил плоским числом. Тело обязано быть ровно
    // тем, что запросило состояние, — и оно обязано быть больше нуля.
    for state in everyState where state != .hidden {
        guard let frame = PanelFrames.frame(for: state, geometry: measured),
              let content = PanelFrames.contentSize(for: state, geometry: measured) else { continue }
        let layout = NotchLayout.inPanel(size: frame.size, geometry: measured)
        #expect(layout.body.height == content.height)
        #expect(layout.body.height > 0)
    }
}

// MARK: - Каждое состояние по отдельности

@Test func peekShowsAThinHintAndNotAZeroHeightBody() {
    // Раньше наведение просило размером ровно вырез: тело выходило нулевой
    // высоты, то есть состояние наведения не показывало ничего.
    let frame = PanelFrames.frame(for: .peek, geometry: measured)
    #expect(frame?.height == measured.rect.height + Config.Notch.peekBodyHeight)
    #expect(Config.Notch.peekBodyHeight > 0)
}

@Test func activityFrameIsWideEnoughForTextAndThumbnail() {
    let frame = PanelFrames.frame(for: .activity, geometry: measured)
    #expect(frame?.width == measured.rect.width + Config.Activity.cardExtraWidth)
    #expect(frame?.height == measured.rect.height + Config.Activity.cardBodyHeight)
}

@Test func activityIsNeverNarrowerThanItsMinimumOnScreensWithoutNotch() {
    let frame = PanelFrames.frame(for: .activity, geometry: plain)
    #expect((frame?.width ?? 0) >= Config.Activity.cardMinWidth)
}

@Test func expandedSizeIsTheContentSizeAndTheNotchIsAddedOnTop() {
    // `expandedSize` — размер СОДЕРЖИМОГО. Раньше это была полная высота
    // окна, из которой вырез съедал 38 точек, и сетка обрезалась.
    let frame = PanelFrames.frame(for: .expanded, geometry: measured)
    #expect(frame?.width == Config.Notch.expandedSize.width)
    #expect(frame?.height == Config.Notch.expandedSize.height + measured.rect.height)
    let layout = NotchLayout.inPanel(size: frame?.size ?? .zero, geometry: measured)
    #expect(layout.body.height == Config.Notch.expandedSize.height)
}

@Test func expandedContentFitsTheHistoryGridAndTheShelfStrip() {
    // Сетка истории и полоса полки живут в теле панели. Если тело меньше
    // полосы полки плюс одной строки плиток — сетка обрезана.
    let needed = Config.Shelf.stripHeight + Config.HistoryGrid.tileSide
    #expect(Config.Notch.expandedSize.height > needed)
}

@Test func onScreenWithoutNotchNothingIsAddedOnTopOfTheContent() {
    let frame = PanelFrames.frame(for: .expanded, geometry: plain)
    #expect(frame?.height == Config.Notch.expandedSize.height)
}

// MARK: - Экрана нет вовсе

@Test func withoutAnyScreenThereIsNoFrameForAnyState() {
    // Вход с ещё не проснувшимся дисплеем: панель ставить некуда, но
    // приложение обязано остаться живым, а не оставить окно в углу экрана.
    for state in everyState {
        #expect(PanelFrames.frame(for: state, geometry: .none) == nil)
    }
}
