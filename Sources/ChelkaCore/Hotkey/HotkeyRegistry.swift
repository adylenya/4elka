import AppKit
import Foundation

/// То, что умеет занять сочетание и отдать его назад. Ровно два действия —
/// больше распорядителю от хоткея не нужно, а подделка в тестах позволяет
/// проверять порядок «снять прежнее, поставить новое» без живой регистрации:
/// живая забирает сочетание у человека, сидящего за этой же машиной.
@MainActor
public protocol HotkeyRegistering: AnyObject {
    /// `nil` — получилось. Иначе причина отказа.
    func register() -> HotkeyFailure?
    /// Идемпотентна: снимать несуществующую регистрацию безопасно.
    func unregister()
}

/// Действующее сочетание приложения: одно на процесс.
///
/// Зачем отдельный тип. Выбор сочетания в настройках сохранялся на диск и не
/// делал ничего: хоткей ставился при старте всегда со значением по умолчанию,
/// а при смене настройки не переставлялся вовсе. Починка требует трёх вещей
/// разом — снять прежнюю регистрацию (она живёт в системе и сама не пропадёт),
/// поставить новую и запомнить отказ, чтобы показать его человеку. В делегате
/// приложения, где и так больше четырёхсот строк, это было бы четвёртым
/// местом, знающим про Carbon.
@MainActor
public final class HotkeyRegistry {
    /// Сочетание, которое сейчас пытается держать приложение. `nil` — не
    /// пытается вовсе (до старта и после выхода).
    public private(set) var combo: HotkeyCombo?
    /// Отказ последней попытки или `nil`, если сочетание за нами.
    public private(set) var failure: HotkeyFailure?

    private var current: HotkeyRegistering?
    private let handler: () -> Void
    private let make: (HotkeyCombo, @escaping () -> Void) -> HotkeyRegistering
    private let log: (String) -> Void

    public init(handler: @escaping () -> Void,
                make: @escaping (HotkeyCombo, @escaping () -> Void) -> HotkeyRegistering
                    = { GlobalHotkey(combo: $0, handler: $1) },
                log: @escaping (String) -> Void = { NSLog("4elka: %@", $0) }) {
        self.handler = handler
        self.make = make
        self.log = log
    }

    /// Держать это сочетание вместо прежнего.
    ///
    /// Зовётся при старте и на каждое изменение настроек — то есть и на правку
    /// квоты истории тоже. Поэтому неизменившееся сочетание не трогается: иначе
    /// каждая посторонняя правка снимала бы регистрацию и ставила заново, а в
    /// окне между этим нажатия уходили бы в пустоту.
    ///
    /// Отказ повторяется на следующем изменении настроек: чужое приложение,
    /// занявшее сочетание, могло закрыться, а перезапускать приложение без
    /// окна и без иконки в доке человеку нечем.
    public func apply(_ combo: HotkeyCombo) {
        guard combo != self.combo || failure != nil else { return }
        release()
        let hotkey = make(combo, handler)
        self.combo = combo
        if let refusal = hotkey.register() {
            failure = refusal
            // В журнал всё равно пишем: причина отказа нужна и в отчёте о
            // проблеме, а не только в окне настроек.
            log(refusal.message)
            return
        }
        current = hotkey
        failure = nil
    }

    /// Отдать сочетание системе. Обязательно при выходе: регистрация живёт в
    /// системе и переживает процесс.
    public func stop() {
        release()
        combo = nil
        failure = nil
    }

    private func release() {
        current?.unregister()
        current = nil
    }
}
