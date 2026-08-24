import Testing
import Foundation
@testable import ChelkaCore

/// Владелец нажал вне раскрытой панели — она не закрылась. Решение «закрывать
/// или нет» — чистая функция от точки клика и рамки панели, а не сам монитор
/// событий: монитор AppKit не проверить тестом, а эту логику — можно.
@Test func clickOutsideThePanelFrameDismissesIt() {
    let panel = CGRect(x: 100, y: 100, width: 400, height: 300)
    #expect(OutsideClickDismissal.shouldDismiss(clickAt: CGPoint(x: 0, y: 0), panelFrame: panel))
}

@Test func clickInsideThePanelFrameDoesNotDismissIt() {
    let panel = CGRect(x: 100, y: 100, width: 400, height: 300)
    #expect(!OutsideClickDismissal.shouldDismiss(clickAt: CGPoint(x: 200, y: 200), panelFrame: panel))
}

@Test func clickOnTheEdgeCountsAsInside() {
    // `CGRect.contains` включает нижнюю и левую границы — клик прямо по краю
    // панели не должен закрывать её же саму.
    let panel = CGRect(x: 100, y: 100, width: 400, height: 300)
    #expect(!OutsideClickDismissal.shouldDismiss(clickAt: CGPoint(x: 100, y: 100), panelFrame: panel))
}

@Test func withoutAPanelFrameNothingDismisses() {
    // Панель уже скрыта — нечему быть «снаружи», и монитор в этот момент
    // не должен быть даже установлен, но если вызов случится — не падать.
    #expect(!OutsideClickDismissal.shouldDismiss(clickAt: CGPoint(x: 0, y: 0), panelFrame: nil))
}
