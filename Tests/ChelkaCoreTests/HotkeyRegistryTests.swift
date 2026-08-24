import Carbon.HIToolbox
import Testing
@testable import ChelkaCore

/// Выбор сочетания в настройках обязан доходить до системы, а отказ
/// регистрации — до человека. Раньше не работало ни то, ни другое: хоткей
/// ставился всегда со значением по умолчанию, а отказ уходил одной строкой в
/// системный журнал, которого у приложения без иконки в доке никто не видит.

@MainActor
private final class Journal {
    private(set) var lines: [String] = []
    func add(_ line: String) { lines.append(line) }
}

/// Подделка регистрации. Живой хоткей забирает сочетание у человека за
/// машиной, а проверять здесь надо порядок вызовов, а не Carbon.
@MainActor
private final class FakeHotkey: HotkeyRegistering {
    private let combo: HotkeyCombo
    private let reason: HotkeyFailure.Reason?
    private let journal: Journal

    init(combo: HotkeyCombo, reason: HotkeyFailure.Reason?, journal: Journal) {
        self.combo = combo
        self.reason = reason
        self.journal = journal
    }

    func register() -> HotkeyFailure? {
        if let reason {
            journal.add("отказ \(combo.displayName)")
            return HotkeyFailure(combo: combo, reason: reason)
        }
        journal.add("ставлю \(combo.displayName)")
        return nil
    }

    func unregister() {
        journal.add("снимаю \(combo.displayName)")
    }
}

@MainActor
private func registry(_ journal: Journal,
                      refuse: @escaping (HotkeyCombo) -> HotkeyFailure.Reason? = { _ in nil })
    -> HotkeyRegistry {
    HotkeyRegistry(handler: {}, make: { combo, _ in
        FakeHotkey(combo: combo, reason: refuse(combo), journal: journal)
    })
}

private let otherCombo = HotkeyCombo(keyCode: UInt32(kVK_ANSI_C),
                                     modifiers: UInt32(controlKey | optionKey))

// MARK: - Сочетание из настроек доходит до системы

@Test func settingsCarryTheComboThatGoesToCarbon() {
    // Настройки хранят два числа со знаком, Carbon принимает беззнаковые.
    // Без этого моста выбор в окне настроек не мог дойти до регистрации даже
    // теоретически: передавать было нечего.
    #expect(Settings.defaults.hotkeyCombo == HotkeyCombo.defaultToggle)

    let chosen = HotkeyChoice(keyCode: Int(kVK_ANSI_C), modifiers: Int(controlKey | optionKey))
    #expect(Settings.defaults.choosing(chosen).hotkeyCombo == otherCombo)
}

@MainActor
@Test func chosenComboIsTheOneRegistered() {
    let journal = Journal()
    let live = registry(journal)
    live.apply(otherCombo)
    #expect(journal.lines == ["ставлю ⌃⌥C"])
    #expect(live.combo == otherCombo)
    #expect(live.failure == nil)
}

@MainActor
@Test func newComboReplacesTheOldRegistrationInsteadOfPilingOnTop() {
    // Регистрация живёт в системе: не снять прежнюю — значит оставить висеть
    // сочетание, которого человек в настройках уже не выбирал.
    let journal = Journal()
    let live = registry(journal)
    live.apply(.defaultToggle)
    live.apply(otherCombo)
    #expect(journal.lines == ["ставлю ⌃⌥V", "снимаю ⌃⌥V", "ставлю ⌃⌥C"])
}

@MainActor
@Test func unrelatedSettingsChangeDoesNotDisturbTheLiveHotkey() {
    // Применение настроек зовётся на любую правку — от квоты истории до
    // тумблера карточек. Снимать и ставить регистрацию заново на каждую из
    // них значит терять нажатия в окне между снятием и постановкой.
    let journal = Journal()
    let live = registry(journal)
    live.apply(.defaultToggle)
    live.apply(.defaultToggle)
    #expect(journal.lines == ["ставлю ⌃⌥V"])
}

@MainActor
@Test func stopHandsTheRegistrationBackBecauseItLivesInTheSystem() {
    let journal = Journal()
    let live = registry(journal)
    live.apply(.defaultToggle)
    live.stop()
    #expect(journal.lines == ["ставлю ⌃⌥V", "снимаю ⌃⌥V"])
    #expect(live.combo == nil)
}

// MARK: - Отказ виден

@MainActor
@Test func refusedRegistrationIsRememberedWithItsReason() {
    let journal = Journal()
    let live = registry(journal, refuse: { _ in .comboTaken })
    live.apply(.defaultToggle)
    #expect(live.failure?.reason == .comboTaken)
    #expect(live.failure?.combo == .defaultToggle)
    // И молчать нельзя: нечего показать — значит человек снова не узнает,
    // почему нажатие ничего не делает.
    #expect(live.failure?.message.isEmpty == false)
}

@MainActor
@Test func refusalIsRetriedOnTheNextSettingsChange() {
    // Чужое приложение, занявшее сочетание, могло закрыться. Отказ навсегда
    // означал бы «до перезапуска», а перезапускать приложение без окна и без
    // иконки в доке человеку нечем.
    let journal = Journal()
    let occupied = Box(true)
    let live = HotkeyRegistry(handler: {}, make: { combo, _ in
        FakeHotkey(combo: combo, reason: occupied.value ? .comboTaken : nil, journal: journal)
    })
    live.apply(.defaultToggle)
    #expect(live.failure != nil)

    occupied.value = false
    live.apply(.defaultToggle)
    #expect(live.failure == nil)
    #expect(journal.lines == ["отказ ⌃⌥V", "ставлю ⌃⌥V"])
}

@MainActor
@Test func refusalDisappearsOnceAnotherComboTakes() {
    let journal = Journal()
    let live = registry(journal, refuse: { $0 == .defaultToggle ? .comboTaken : nil })
    live.apply(.defaultToggle)
    #expect(live.failure != nil)
    live.apply(otherCombo)
    #expect(live.failure == nil)
}

@Test func refusalReasonsDoNotShareOneLyingMessage() {
    // `register()` возвращал `false` и когда сочетание занято чужим
    // приложением, и когда этот же экземпляр уже зарегистрирован, а печаталось
    // одно и то же — «занято другим приложением». То есть текст мог врать.
    let combo = HotkeyCombo.defaultToggle
    let messages = [HotkeyFailure(combo: combo, reason: .comboTaken).message,
                    HotkeyFailure(combo: combo, reason: .alreadyRegistered).message,
                    HotkeyFailure(combo: combo, reason: .systemRefused(-50)).message]
    #expect(Set(messages).count == 3)
    // В каждом случае человек должен видеть, о каком сочетании речь.
    #expect(messages.allSatisfy { $0.contains(combo.displayName) })
    // Незнакомый код системы называется числом: иначе о нём нечего сказать
    // даже автору.
    #expect(messages[2].contains("-50"))
}

// MARK: - Настоящая регистрация

@MainActor
@Test func sameInstanceRegisteringTwiceIsNotBlamedOnAnotherApp() {
    let hotkey = GlobalHotkey(combo: HotkeyCombo.defaultToggle, handler: {})
    #expect(hotkey.register() == nil)
    // Своя ошибка вызывающего: сочетание не занято никем чужим.
    #expect(hotkey.register()?.reason == .alreadyRegistered)

    let rival = GlobalHotkey(combo: HotkeyCombo.defaultToggle, handler: {})
    #expect(rival.register()?.reason == .comboTaken)

    hotkey.unregister()
    rival.unregister()
}

@MainActor
@Test func replacedComboIsHandedBackToTheSystemForReal() {
    // Подделка выше проверяет порядок вызовов, а здесь — что снятие
    // настоящее: после смены сочетания прежнее обязано снова регистрироваться.
    let live = HotkeyRegistry(handler: {})
    live.apply(.defaultToggle)
    live.apply(otherCombo)

    let probe = GlobalHotkey(combo: .defaultToggle, handler: {})
    #expect(probe.register() == nil, "прежнее сочетание осталось занятым нами же")
    probe.unregister()
    live.stop()
}

/// Изменяемая величина для подделки: замыкание `make` не может захватить
/// локальную переменную теста на запись.
@MainActor
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
