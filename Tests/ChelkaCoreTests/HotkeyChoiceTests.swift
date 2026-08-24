import Carbon.HIToolbox
import Testing
@testable import ChelkaCore

/// Список сочетаний, предлагаемых в настройках, целиком — а не одно сочетание
/// по умолчанию. Ревью нашло в нём четыре комбинации, занятые системой:
/// человек выбирал `⌥Пробел` и терял неразрывный пробел во всех текстовых
/// полях, выбирал `⌃Пробел` — и переставала переключаться раскладка.

@Test func offeredHotkeysAvoidCombosTheSystemAlreadyTook() {
    for choice in HotkeyChoice.all {
        let taken = HotkeyChoice.takenBySystem(choice)
        #expect(taken == nil,
                "в настройках предлагается \(choice.displayName): \(taken?.takenBy ?? "")")
    }
}

@Test func combosFoundByTheReviewAreNamedTakenNotJustDropped() {
    // Убрать их из списка мало: без явной таблицы с объяснением, чем каждое
    // занято, следующий вернёт их обратно — именно так они там и оказались.
    let taken = [HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(controlKey)),
                 HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(optionKey)),
                 HotkeyChoice(keyCode: Int(kVK_ANSI_C), modifiers: Int(cmdKey | shiftKey)),
                 HotkeyChoice(keyCode: Int(kVK_ANSI_B), modifiers: Int(cmdKey | shiftKey)),
                 // Про это сочетание `Config.Hotkey` объясняет на тридцать
                 // строк, а таблица обязана знать о нём наравне с остальными.
                 HotkeyChoice(keyCode: Int(kVK_ANSI_V), modifiers: Int(cmdKey | shiftKey))]
    for combo in taken {
        #expect(!HotkeyChoice.all.contains(combo),
                "\(combo.displayName) всё ещё предлагается в настройках")
        #expect(HotkeyChoice.takenBySystem(combo) != nil,
                "\(combo.displayName) не назван занятым — значит вернётся в список")
    }
}

@Test func everyForbiddenComboSaysWhatExactlyTookIt() {
    // Таблица без объяснений — это тот же список без объяснений: по нему
    // нельзя ни проверить утверждение, ни понять, устарело ли оно.
    #expect(!HotkeyChoice.forbidden.isEmpty)
    for entry in HotkeyChoice.forbidden {
        #expect(!entry.takenBy.isEmpty, "\(entry.choice.displayName) без объяснения")
    }
}

@Test func offeredListStillGivesSomethingToChooseFrom() {
    // Вычистить список до одной строки — тоже отказ от настройки: выбирать
    // будет не из чего.
    #expect(HotkeyChoice.all.contains(HotkeyChoice.defaultChoice))
    #expect(HotkeyChoice.all.count >= 3)
    // Каждое предлагаемое сочетание должно быть читаемым: «?» вместо клавиши
    // означает, что подписи для неё нет.
    #expect(HotkeyChoice.all.allSatisfy { !$0.displayName.contains("?") })
    // Одинаковых строк в списке быть не может: выбор идёт по признаку
    // сочетания, и два одинаковых пункта означают потерянный пункт.
    #expect(Set(HotkeyChoice.all.map(\.id)).count == HotkeyChoice.all.count)
}

@Test func forbiddenComboSavedByAnOlderVersionIsReplacedOnLoad() {
    // Список выбора когда-то предлагал ⌥Пробел, и у того, кто его выбрал, он
    // так и лежит в файле настроек. Убрать пункт из списка недостаточно:
    // проверка значений обязана отменить и уже сохранённый выбор.
    var stored = Settings.defaults
    stored.hotkeyKeyCode = Int(kVK_Space)
    stored.hotkeyModifiers = Int(optionKey)
    #expect(stored.sanitized().hotkeyChoice == HotkeyChoice.defaultChoice)
}

@Test func hotkeyModifiersFromAHandEditedFileLoseUnknownBits() {
    // В файл настроек можно вписать что угодно, а маска модификаторов уходит
    // в Carbon числом. Отрицательное значение проходило проверку «есть хоть
    // один настоящий модификатор» и превращалось в мусор при переводе в
    // беззнаковое.
    var stored = Settings.defaults
    stored.hotkeyModifiers = -1
    let fixed = stored.sanitized()
    #expect(fixed.hotkeyModifiers >= 0)
    #expect(fixed.hotkeyModifiers & ~Config.Hotkey.knownModifiers == 0)
}
