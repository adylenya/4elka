import Foundation
import SwiftUI

/// Единственный владелец настроек в приложении. Окно настроек пишет сюда,
/// подсистемы читают отсюда — не каждая свою копию с диска.
///
/// `@MainActor`, потому что за ним сидит интерфейс. Само значение настроек —
/// тип из одних значений, менять его можно только целиком: `update` получает
/// текущее, возвращает новое.
@MainActor
public final class SettingsController: ObservableObject {
    @Published public private(set) var settings: Settings

    private let store: SettingsStore

    /// Кому сообщить, что настройки изменились. Ставит `ChelkaAppDelegate`:
    /// часть настроек нужно применить сразу (квоты истории), а не при
    /// следующем событии.
    public var onChange: ((Settings) -> Void)?

    public init(store: SettingsStore) {
        self.store = store
        settings = store.load()
    }

    /// Изменение одним куском: новое значение прогоняется через `sanitized()`
    /// и сохраняется. Если оно совпало с текущим, ничего не происходит —
    /// иначе биндинг, дёрнутый на перерисовке, писал бы файл на каждый кадр.
    public func update(_ transform: (Settings) -> Settings) {
        let next = transform(settings).sanitized()
        guard next != settings else { return }
        settings = next
        store.save(next)
        onChange?(next)
    }

    /// Биндинг на одно поле для `Form`. Через `update`, а не напрямую в
    /// хранимое значение: так проверка и сохранение не могут быть забыты
    /// на очередном новом поле.
    public func binding<T>(_ keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { value in
                    self.update { current in
                        var next = current
                        next[keyPath: keyPath] = value
                        return next
                    }
                })
    }
}
