import Testing
import Foundation
@testable import ChelkaCore

@Test func selectionTogglesAndReplaces() {
    let a = UUID(), b = UUID()
    #expect(Selection().toggling(a).ids == [a])
    #expect(Selection().toggling(a).toggling(a).ids.isEmpty)
    #expect(Selection().toggling(a).toggling(b).ids == [a, b])
    #expect(Selection().toggling(a).toggling(b).replacing(with: a).ids == [a])
    #expect(Selection().toggling(a).cleared().ids.isEmpty)
}

/// Главное в сужении: выделенное на другой вкладке (или отсеянное поиском)
/// не должно попасть под `⌫` и `⌘P`. Человек этого элемента не видит, отмены
/// у нас нет, и удалялся он молча — вместе с тем, что человек действительно
/// выделил.
@Test func narrowingKeepsOnlyVisibleIDs() {
    let visible = UUID(), hidden = UUID()
    let narrowed = Selection(ids: [visible, hidden]).narrowed(to: [visible])
    #expect(narrowed.ids == [visible])
}

/// Порядок выделения сохраняется и после сужения: в нём элементы уйдут
/// в перетаскивание.
@Test func narrowingKeepsSelectionOrder() {
    let a = UUID(), b = UUID(), c = UUID()
    #expect(Selection(ids: [c, a, b]).narrowed(to: [a, b, c]).ids == [c, a, b])
}

/// Вкладка, на которой не видно ни одного выделенного элемента, снимает
/// выделение целиком — иначе `⌫` работал бы по невидимому.
@Test func narrowingToNothingVisibleClearsSelection() {
    #expect(Selection(ids: [UUID(), UUID()]).narrowed(to: []).isEmpty)
}

/// Видимое, но не выделенное, выделением не становится.
@Test func narrowingDoesNotAddVisibleItemsToSelection() {
    let selected = UUID()
    #expect(Selection(ids: [selected]).narrowed(to: [selected, UUID()]).ids == [selected])
}
