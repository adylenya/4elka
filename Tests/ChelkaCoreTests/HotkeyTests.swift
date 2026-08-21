import Carbon.HIToolbox
import Testing
@testable import ChelkaCore

@Test func defaultComboDoesNotStealPasteWithoutFormatting() {
    // ⌘⇧V брать нельзя: это системная «вставка без форматирования» почти во
    // всех редакторах и браузерах, а глобальная регистрация забирает сочетание
    // себе. Тест закрепляет именно это требование, а не конкретные клавиши:
    // сочетание по умолчанию обязано быть не ⌘⇧V.
    let combo = HotkeyCombo.defaultToggle
    let pasteWithoutFormatting = HotkeyCombo(keyCode: UInt32(kVK_ANSI_V),
                                             modifiers: UInt32(cmdKey | shiftKey))
    #expect(combo != pasteWithoutFormatting)
    #expect(combo.keyCode == UInt32(kVK_ANSI_V))
    #expect(combo.modifiers == UInt32(controlKey | optionKey))
}

@Test func displayNameIsHumanReadable() {
    #expect(HotkeyCombo.defaultToggle.displayName == "⌃⌥V")
}

@Test func displayNameKeepsModifiersInOneStableOrder() {
    // Порядок значков фиксирован планом: команда первой (отсюда «⌘⇧V»),
    // дальше остальные модификаторы. Проверяем на всех модификаторах разом.
    let combo = HotkeyCombo(keyCode: UInt32(kVK_Space),
                            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
    #expect(combo.displayName == "⌘⌃⌥⇧Space")
}

@Test func displayNameMarksUnknownKeyInsteadOfLying() {
    // Клавиши, для которой нет подписи, быть в настройках не должно, но
    // молча показывать пустое место нельзя — иначе сочетание выглядит как
    // «только модификаторы».
    let combo = HotkeyCombo(keyCode: 0xFFFF, modifiers: UInt32(cmdKey))
    #expect(combo.displayName == "⌘?")
}

// Регистрация в Carbon — процессный ресурс, поэтому тесты ниже синхронные и
// живут на главном акторе: два синхронных теста на главном акторе не могут
// переплестись и подраться за одну и ту же комбинацию.

@MainActor
@Test func registrationSucceedsAndCanBeRepeatedAfterUnregister() {
    let first = GlobalHotkey(combo: HotkeyCombo.defaultToggle, handler: {})
    #expect(first.register())
    first.unregister()

    let second = GlobalHotkey(combo: HotkeyCombo.defaultToggle, handler: {})
    #expect(second.register())
    second.unregister()
}

@MainActor
@Test func doubleRegistrationOfSameComboIsReportedNotCrashed() {
    let hits = Counter()
    let a = GlobalHotkey(combo: HotkeyCombo.defaultToggle) { hits.bump("a") }
    let b = GlobalHotkey(combo: HotkeyCombo.defaultToggle) { hits.bump("b") }
    #expect(a.register())
    // Второй регистратор на ту же комбинацию должен честно вернуть false.
    #expect(!b.register())
    #expect(b.identifier == nil)

    // И не отнять сочетание у первого: неудачная попытка ничего не ломает.
    if let identifier = a.identifier { GlobalHotkey.dispatch(identifier) }
    #expect(hits.counts == ["a": 1])

    a.unregister()
    b.unregister()
}

@MainActor
@Test func unregisterWithoutRegistrationChangesNothing() {
    let hotkey = GlobalHotkey(combo: HotkeyCombo.defaultToggle, handler: {})
    hotkey.unregister()
    hotkey.unregister()
    #expect(hotkey.identifier == nil)
}

@MainActor
@Test func pressDeliveredToItsOwnHandlerOnly() {
    // Синтетических нажатий мы не посылаем — дёргаем распределитель напрямую,
    // тем же путём, которым его зовёт обработчик Carbon.
    let hits = Counter()
    let toggle = GlobalHotkey(combo: HotkeyCombo.defaultToggle) { hits.bump("toggle") }
    let other = GlobalHotkey(combo: HotkeyCombo(keyCode: UInt32(kVK_ANSI_C),
                                                modifiers: UInt32(cmdKey | shiftKey))) {
        hits.bump("other")
    }
    #expect(toggle.register())
    #expect(other.register())
    defer {
        toggle.unregister()
        other.unregister()
    }

    guard let toggleID = toggle.identifier, let otherID = other.identifier else {
        Issue.record("регистрация не выдала идентификатор")
        return
    }
    #expect(toggleID != otherID)

    GlobalHotkey.dispatch(toggleID)
    #expect(hits.counts == ["toggle": 1])
}

@MainActor
@Test func pressAfterUnregisterReachesNobody() {
    let hits = Counter()
    let hotkey = GlobalHotkey(combo: HotkeyCombo.defaultToggle) { hits.bump("toggle") }
    #expect(hotkey.register())
    guard let identifier = hotkey.identifier else {
        Issue.record("регистрация не выдала идентификатор")
        return
    }
    hotkey.unregister()

    GlobalHotkey.dispatch(identifier)
    #expect(hits.counts.isEmpty)
    #expect(hotkey.identifier == nil)
}

/// Счётчик вызовов для подделок: обработчик хоткея ничего не возвращает, и
/// иначе его срабатывание не увидеть.
private final class Counter {
    private(set) var counts: [String: Int] = [:]

    func bump(_ key: String) {
        counts[key, default: 0] += 1
    }
}
