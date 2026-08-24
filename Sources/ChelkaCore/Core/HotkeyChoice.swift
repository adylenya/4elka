import Carbon.HIToolbox
import Foundation

/// Комбинация клавиш, раскрывающая панель, в карбоновых кодах — тех самых,
/// что принимает `RegisterEventHotKey`. Тип из одних значений: `Sendable`
/// достаётся бесплатно, окон не трогает.
///
/// Настройки предлагают выбор из готового списка, а не запись любой
/// комбинации с клавиатуры. Причина: перехватчик нажатий поверх окна ловил
/// бы и служебные комбинации системы, а проверить такое можно только руками —
/// то есть никак, потому что за машиной работает владелец. Список выбора
/// проверяется тестом, а сама регистрация — забота задачи про хоткей.
public struct HotkeyChoice: Equatable, Sendable, Identifiable {
    public let keyCode: Int
    public let modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var id: String { "\(modifiers)-\(keyCode)" }

    /// Подпись комбинации значками: ⌘⇧V. ⌘ ставится первым — так эта
    /// комбинация названа и в задании, и так её называет владелец.
    public var displayName: String {
        var text = ""
        if modifiers & Int(controlKey) != 0 { text += "⌃" }
        if modifiers & Int(optionKey) != 0 { text += "⌥" }
        if modifiers & Int(shiftKey) != 0 { text += "⇧" }
        if modifiers & Int(cmdKey) != 0 { text = "⌘" + text }
        return text + (Self.keyNames[keyCode] ?? "?")
    }

    public static let defaultChoice = HotkeyChoice(keyCode: Config.Hotkey.keyCode,
                                                  modifiers: Config.Hotkey.modifiers)

    /// Что предлагается в настройках. Только комбинации с ⌘/⌃/⌥: без них
    /// хоткей отобрал бы обычную букву во всех приложениях сразу.
    ///
    /// Список короткий сознательно. Прежний был длиннее вчетверо и предлагал
    /// `⌥Пробел`, `⌃Пробел`, `⌘⇧C` и `⌘⌥V` — то есть отбирал у человека
    /// неразрывный пробел, переключение раскладки, пункт Finder и перенос
    /// файлов. Остались только сочетания `⌃⌥` с буквой: единственное
    /// семейство, за которым не стоит ни системного действия из справки
    /// Apple, ни пункта меню Finder и Safari. Чем занято каждое выброшенное —
    /// в таблице `forbidden` ниже.
    public static let all: [HotkeyChoice] = [
        defaultChoice,
        HotkeyChoice(keyCode: Int(kVK_ANSI_C), modifiers: Int(controlKey | optionKey)),
        HotkeyChoice(keyCode: Int(kVK_ANSI_B), modifiers: Int(controlKey | optionKey)),
    ]

    /// Сочетание, которое занимать нельзя, и то, чем именно оно занято.
    ///
    /// Пара «сочетание — объяснение», а не просто список: без объяснения
    /// следующий вернёт выброшенное обратно, как это уже и произошло. Каждая
    /// строка — проверяемое утверждение, и если оно устареет, будет видно, что
    /// именно перепроверять.
    public struct Forbidden: Equatable, Sendable {
        public let choice: HotkeyChoice
        public let takenBy: String

        public init(_ choice: HotkeyChoice, takenBy: String) {
            self.choice = choice
            self.takenBy = takenBy
        }
    }

    /// Занятое системой и повседневными приложениями. Глобальная регистрация
    /// забирает сочетание себе целиком, поэтому любая строка отсюда означает
    /// сломанную привычку: человек жмёт то же, что и раньше, и получает не то.
    public static let forbidden: [Forbidden] = [
        Forbidden(HotkeyChoice(keyCode: Int(kVK_ANSI_V), modifiers: Int(cmdKey | shiftKey)),
                  takenBy: "«Вставить без форматирования» — почти во всех редакторах и браузерах"),
        Forbidden(HotkeyChoice(keyCode: Int(kVK_ANSI_V), modifiers: Int(cmdKey | optionKey)),
                  takenBy: "Finder: «Переместить объект сюда»"),
        Forbidden(HotkeyChoice(keyCode: Int(kVK_ANSI_C), modifiers: Int(cmdKey | shiftKey)),
                  takenBy: "Finder: переход в «Компьютер»"),
        Forbidden(HotkeyChoice(keyCode: Int(kVK_ANSI_B), modifiers: Int(cmdKey | shiftKey)),
                  takenBy: "Safari: «Панель закладок»"),
        Forbidden(HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(controlKey)),
                  takenBy: "система: «Выбрать предыдущий источник ввода» — переключение раскладки"),
        Forbidden(HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(controlKey | optionKey)),
                  takenBy: "система: «Выбрать следующий источник ввода в меню ввода»"),
        Forbidden(HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(optionKey)),
                  takenBy: "неразрывный пробел — набирается в любом текстовом поле"),
        Forbidden(HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(cmdKey)),
                  takenBy: "система: Spotlight"),
        Forbidden(HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(cmdKey | optionKey)),
                  takenBy: "система: окно поиска Finder"),
        Forbidden(HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(cmdKey | controlKey)),
                  takenBy: "система: панель «Эмодзи и символы»"),
        Forbidden(HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(cmdKey | shiftKey)),
                  takenBy: "занят пробелом с модификаторами: соседние ⌘⌥Пробел и ⌃⌘Пробел уже " +
                           "системные, и промахнуться мимо них проще, чем нажать нужное"),
    ]

    /// Кто занял это сочетание, или `nil`, если оно свободно. По этому же
    /// правилу проверка значений отменяет сочетание, сохранённое прошлой
    /// версией: пункт из списка убрать легко, а из файла настроек он никуда
    /// не денется.
    public static func takenBySystem(_ choice: HotkeyChoice) -> Forbidden? {
        forbidden.first { $0.choice == choice }
    }

    /// Сочетание в том виде, в каком его принимает `RegisterEventHotKey`.
    /// Мост между настройками (числа со знаком, так они лежат в файле) и
    /// Carbon (беззнаковые): без него выбор в окне настроек никуда не уходил.
    ///
    /// Перевод через `truncatingIfNeeded`, а не `UInt32(_:)`: тот падает на
    /// отрицательном числе, а в файл настроек можно вписать что угодно.
    /// Проверка значений отрицательные маски отсекает, но падение из-за
    /// правки файла руками — слишком дорогая расплата за одну строку.
    public var combo: HotkeyCombo {
        HotkeyCombo(keyCode: UInt32(truncatingIfNeeded: keyCode),
                    modifiers: UInt32(truncatingIfNeeded: modifiers))
    }

    private static let keyNames: [Int: String] = [
        Int(kVK_ANSI_V): "V",
        Int(kVK_ANSI_C): "C",
        Int(kVK_ANSI_B): "B",
        Int(kVK_Space): "Пробел",
    ]
}
