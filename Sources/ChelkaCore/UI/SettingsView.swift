import SwiftUI

/// Действия, которых окно настроек не может выполнить само: они живут в
/// делегате приложения (очистка истории — у координатора буфера, автозапуск —
/// у системной службы). Окно их только зовёт.
public struct SettingsActions {
    public let clearHistory: () -> Void
    public let isLaunchAtLoginEnabled: () -> Bool
    public let toggleLaunchAtLogin: () -> Void
    public let revealDataFolder: () -> Void

    public init(clearHistory: @escaping () -> Void,
                isLaunchAtLoginEnabled: @escaping () -> Bool,
                toggleLaunchAtLogin: @escaping () -> Void,
                revealDataFolder: @escaping () -> Void) {
        self.clearHistory = clearHistory
        self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
        self.toggleLaunchAtLogin = toggleLaunchAtLogin
        self.revealDataFolder = revealDataFolder
    }
}

/// Окно настроек: обычное окно, а не панель над челкой. Один длинный `Form`
/// с разделами вместо вкладок — разделов восемь, и вкладками пришлось бы
/// угадывать, в какой из них лежит нужное.
///
/// Тема системная. Своих цветов здесь нет ни одного: всё рисуют системные
/// элементы управления, пояснения идут семантическим `.secondary`. Выбора
/// темы в окне нет и быть не должно — переключение светлая/тёмная достаётся
/// от системы бесплатно.
///
/// Сохранение — при каждом изменении, через `SettingsController.update`,
/// который прогоняет значение через `sanitized()` и пишет файл атомарно.
/// Кнопки «Применить» нет намеренно: настройки маленькие, и забытое нажатие
/// «Применить» — верный способ решить, что приложение не работает.
public struct SettingsView: View {
    @ObservedObject private var controller: SettingsController
    private let actions: SettingsActions

    public init(controller: SettingsController, actions: SettingsActions) {
        self.controller = controller
        self.actions = actions
    }

    public var body: some View {
        Form {
            ClipboardSettingsSection(controller: controller)
            CardsSettingsSection(controller: controller)
            BatterySettingsSection(controller: controller)
            WeatherSettingsSection(controller: controller)
            CalendarSettingsSection(controller: controller)
            PlayerSettingsSection(controller: controller)
            BehaviorSettingsSection(controller: controller, actions: actions)
            DataSettingsSection(actions: actions)
        }
        .formStyle(.grouped)
        .frame(minWidth: Config.SettingsWindow.minSize.width,
               minHeight: Config.SettingsWindow.minSize.height)
    }
}
