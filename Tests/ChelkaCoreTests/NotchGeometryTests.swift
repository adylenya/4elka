import Testing
import AppKit
@testable import ChelkaCore

@Test func computesNotchFromMeasuredScreenValues() {
    let g = NotchGeometry.compute(
        screenFrame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
        safeAreaTop: 38,
        auxLeft: CGRect(x: 0, y: 1291, width: 918, height: 38),
        auxRight: CGRect(x: 1138, y: 1291, width: 918, height: 38),
        menuBarHeight: 38
    )
    #expect(g.hasPhysicalNotch)
    #expect(g.rect.width == 220)
    #expect(g.rect.height == 38)
    #expect(g.rect.midX == 1028)
    #expect(g.rect.maxY == 1329)
}

@Test func fallsBackToCenteredPillWhenNoNotch() {
    let g = NotchGeometry.compute(
        screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0, auxLeft: nil, auxRight: nil,
        menuBarHeight: 0
    )
    #expect(!g.hasPhysicalNotch)
    #expect(g.rect.width == Config.Notch.fallbackWidth)
    #expect(g.rect.height == Config.Notch.fallbackHeight)
    #expect(g.rect.midX == 960)
    #expect(g.rect.maxY == 1080)
}

@Test func fallbackPillDoesNotCoverTheMenuBar() {
    // Запасная плашка стоит уровнем выше строки меню и принимает мышь. Пока
    // она лежала у самого верха экрана, клик по заголовку меню на внешнем
    // мониторе открывал панель 4elka вместо самого меню.
    let menuBar: CGFloat = 24
    let g = NotchGeometry.compute(
        screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0, auxLeft: nil, auxRight: nil,
        menuBarHeight: menuBar
    )
    #expect(g.rect.maxY == 1080 - menuBar)
}

@Test func fallsBackWhenOnlyOneAuxiliaryAreaIsPresent() {
    let g = NotchGeometry.compute(
        screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0,
        auxLeft: CGRect(x: 0, y: 1042, width: 800, height: 38),
        auxRight: nil,
        menuBarHeight: 0
    )
    #expect(!g.hasPhysicalNotch)
}

@Test func handlesNonZeroScreenOrigin() {
    let g = NotchGeometry.compute(
        screenFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0, auxLeft: nil, auxRight: nil,
        menuBarHeight: 0
    )
    #expect(g.rect.midX == -960)
}
