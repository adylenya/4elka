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
    public static let all: [HotkeyChoice] = [
        defaultChoice,
        HotkeyChoice(keyCode: Int(kVK_ANSI_V), modifiers: Int(cmdKey | optionKey)),
        HotkeyChoice(keyCode: Int(kVK_ANSI_C), modifiers: Int(cmdKey | shiftKey)),
        HotkeyChoice(keyCode: Int(kVK_ANSI_B), modifiers: Int(cmdKey | shiftKey)),
        HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(cmdKey | shiftKey)),
        HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(optionKey)),
        HotkeyChoice(keyCode: Int(kVK_Space), modifiers: Int(controlKey)),
    ]

    private static let keyNames: [Int: String] = [
        Int(kVK_ANSI_V): "V",
        Int(kVK_ANSI_C): "C",
        Int(kVK_ANSI_B): "B",
        Int(kVK_Space): "Пробел",
    ]
}
