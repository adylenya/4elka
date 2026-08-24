import AppKit
import Testing
import Foundation
@testable import ChelkaCore

/// События создаются как ОБЪЕКТЫ и отдаются вью напрямую. Ни одно из них в
/// систему не посылается: синтетические нажатия — это чужой компьютер, а не тест.
private func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent? {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
}

@MainActor
private func view() -> DragSourceView {
    DragSourceView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
}

/// Тащить нечего: блоб исчез с диска, или у записи «файлы» пустой список.
/// Точка нажатия обнулялась ДО проверки на пустоту, и отпускание кнопки уже не
/// видело нажатия — плитка не отзывалась ни на жест, ни на клик.
@Test @MainActor func emptyDragResultStillDeliversClick() throws {
    let v = view()
    v.urlsForDrag = { [] }
    var clicks = 0
    v.onClick = { _ in clicks += 1 }

    v.mouseDown(with: try #require(mouse(.leftMouseDown, at: .zero)))
    v.mouseDragged(with: try #require(mouse(.leftMouseDragged, at: NSPoint(x: 50, y: 50))))
    v.mouseUp(with: try #require(mouse(.leftMouseUp, at: NSPoint(x: 50, y: 50))))

    #expect(clicks == 1)
}

/// Дрожь руки — не жест: пока порог не перешагнут, файлы даже не готовятся
/// (а готовятся они копированием на диск).
@Test @MainActor func moveBelowThresholdDoesNotPrepareFiles() throws {
    let v = view()
    var asked = 0
    v.urlsForDrag = { asked += 1; return [] }

    v.mouseDown(with: try #require(mouse(.leftMouseDown, at: .zero)))
    v.mouseDragged(with: try #require(mouse(.leftMouseDragged, at: NSPoint(x: 1, y: 1))))

    #expect(asked == 0)
}

/// Пустой результат — не повод готовить файлы заново на каждое движение мыши
/// внутри того же нажатия: это десятки попыток и десятки строк в логе.
@Test @MainActor func emptyDragResultIsAskedOnlyOncePerPress() throws {
    let v = view()
    var asked = 0
    v.urlsForDrag = { asked += 1; return [] }

    v.mouseDown(with: try #require(mouse(.leftMouseDown, at: .zero)))
    v.mouseDragged(with: try #require(mouse(.leftMouseDragged, at: NSPoint(x: 50, y: 50))))
    v.mouseDragged(with: try #require(mouse(.leftMouseDragged, at: NSPoint(x: 60, y: 60))))

    #expect(asked == 1)
}

/// Нажатие без сдвига — обычный клик по плитке.
@Test @MainActor func pressWithoutMovementIsAClick() throws {
    let v = view()
    var clicks = 0
    v.onClick = { _ in clicks += 1 }

    v.mouseDown(with: try #require(mouse(.leftMouseDown, at: .zero)))
    v.mouseUp(with: try #require(mouse(.leftMouseUp, at: .zero)))

    #expect(clicks == 1)
}
