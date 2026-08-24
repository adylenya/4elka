import Carbon.HIToolbox
import Foundation

/// Сочетание клавиш: код клавиши и маска модификаторов в терминах Carbon.
/// Тип из одних значений, поэтому `Sendable` достаётся бесплатно.
public struct HotkeyCombo: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultToggle = HotkeyCombo(keyCode: Config.Hotkey.defaultKeyCode,
                                                 modifiers: Config.Hotkey.defaultModifiers)

    /// Подпись сочетания значками: команда первой, дальше остальные модификаторы
    /// и клавиша. Порядок фиксированный — иначе одно и то же сочетание
    /// выглядело бы в настройках по-разному от запуска к запуску.
    public var displayName: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text = "⌘" + text }
        return text + (Self.keyNames[keyCode] ?? "?")
    }

    /// Подписи клавиш, которые сочетание вообще может занимать. Полная
    /// раскладка тут не нужна: незнакомая клавиша честно рисуется как «?».
    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_Space): "Space",
    ]
}

/// Глобальный хоткей на Carbon `RegisterEventHotKey`.
///
/// Carbon вместо современного API сознательно: `NSEvent.addGlobalMonitorForEvents`
/// и `CGEventTap` требуют разрешения «Управление компьютером», а
/// `RegisterEventHotKey` не требует никаких разрешений вовсе — приложение
/// получает только своё сочетание и ничего больше не подслушивает.
///
/// Одна регистрация на экземпляр. Кто и когда её ставит, кто снимает прежнюю
/// при смене сочетания и кто показывает отказ человеку — забота
/// `HotkeyRegistry`: здесь только разговор с Carbon.
///
/// Класс живёт на главном акторе: регистрация трогает событийную цель
/// приложения, а обработчик в итоге двигает окно панели. Обработчик Carbon
/// приходит через C-указатель на функцию, про который компилятор ничего не
/// знает, поэтому доставка переносится на главный актор явно — в `dispatch`.
@MainActor
public final class GlobalHotkey {
    /// Общий на процесс распределитель: Carbon отдаёт нам только числовой
    /// идентификатор нажатого сочетания, по нему и находим обработчик.
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextIdentifier: UInt32 = 1
    /// Устанавливается один раз и живёт до конца процесса: снимать и ставить
    /// его заново на каждую регистрацию — лишний риск без выгоды, сам по себе
    /// он ничего не делает, пока в `handlers` никого нет.
    private static var dispatcher: EventHandlerRef?

    private let combo: HotkeyCombo
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    /// Идентификатор действующей регистрации, `nil` — если её нет.
    private(set) var identifier: UInt32?

    public init(combo: HotkeyCombo, handler: @escaping () -> Void) {
        self.combo = combo
        self.handler = handler
    }

    /// `nil` означает «получилось». Иначе — причина отказа: вызывающий обязан
    /// сказать о ней человеку, а не промолчать.
    ///
    /// Причина, а не `false`: отказ приходит и когда сочетание занято чужим
    /// приложением, и когда этот же экземпляр уже зарегистрирован, а раньше
    /// на оба случая печаталось «занято другим приложением» — то есть текст
    /// мог врать.
    public func register() -> HotkeyFailure? {
        guard hotKeyRef == nil else {
            return HotkeyFailure(combo: combo, reason: .alreadyRegistered)
        }
        Self.installDispatcherIfNeeded()

        let identifier = Self.nextIdentifier
        let eventID = EventHotKeyID(signature: Config.Hotkey.signature, id: identifier)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, eventID,
                                        GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            let reason: HotkeyFailure.Reason = status == eventHotKeyExistsErr
                ? .comboTaken
                : .systemRefused(status)
            return HotkeyFailure(combo: combo, reason: reason)
        }

        Self.nextIdentifier += 1
        hotKeyRef = ref
        self.identifier = identifier
        Self.handlers[identifier] = handler
        return nil
    }

    /// Идемпотентна: снимать несуществующую регистрацию безопасно.
    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let identifier { Self.handlers.removeValue(forKey: identifier) }
        hotKeyRef = nil
        identifier = nil
    }

    /// Точка входа доставки: зовётся обработчиком Carbon и тестами. Нажатие на
    /// снятую регистрацию не находит обработчика и тихо ничего не делает.
    static func dispatch(_ identifier: UInt32) {
        handlers[identifier]?()
    }

    private static func installDispatcherIfNeeded() {
        guard dispatcher == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var received = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &received)
            guard status == noErr else { return status }
            // Тело замыкания — C-функция без захватов, поэтому переносим на
            // главный актор только число: обещать изоляцию нельзя, её надо
            // взять явно.
            let identifier = received.id
            Task { @MainActor in GlobalHotkey.dispatch(identifier) }
            return noErr
        }, 1, &spec, nil, &dispatcher)
    }
}

/// Регистрация настоящая — та, что уходит в Carbon. Подделка с тем же
/// протоколом живёт в тестах распорядителя.
extension GlobalHotkey: HotkeyRegistering {}
