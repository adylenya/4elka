import AppKit

/// Действия, доступные из меню иконки в строке меню.
public enum StatusMenuAction: Equatable, Sendable, CaseIterable {
    case showPanel, hidePanel, openSettings, toggleLaunchAtLogin, quit
}

/// Состав и подписи меню — чистая функция без окон и системных вызовов.
/// Это единственная часть, которую можно проверить тестом, и именно на ней
/// держится гарантия «выход есть всегда».
public enum StatusMenu {
    /// Пункты меню для текущего состояния. Про автозапуск здесь ничего не
    /// нужно: он влияет только на подпись пункта, а не на состав меню.
    public static func items(panel: PanelState) -> [StatusMenuAction] {
        var items: [StatusMenuAction] = []
        // Раскрытая панель предлагает обратное действие, а не прячет пункт
        // совсем: раньше при раскрытой панели меню не предлагало ничего, и
        // единственным выходом оставалось выключить приложение.
        items.append(panel == .expanded ? .hidePanel : .showPanel)
        items.append(.openSettings)
        items.append(.toggleLaunchAtLogin)
        // Выход есть всегда и при любом состоянии: это аварийный выход,
        // и отключаемым он быть не может.
        items.append(.quit)
        return items
    }

    public static func title(for action: StatusMenuAction, launchesAtLogin: Bool) -> String {
        switch action {
        case .showPanel: return "Показать панель"
        case .hidePanel: return "Скрыть панель"
        case .openSettings: return "Настройки…"
        case .toggleLaunchAtLogin:
            // Подпись про действие, которое произойдёт по клику, а не про
            // текущее состояние — иначе непонятно, включено сейчас или это
            // предложение включить.
            return launchesAtLogin ? "Не запускать при входе" : "Запускать при входе"
        case .quit: return "Выключить 4elka"
        }
    }
}

/// Иконка в строке меню. Единственный способ управлять приложением и
/// аварийный выход из него: у приложения нет иконки в доке, а панель живёт
/// только над челкой.
@MainActor
public final class StatusItemController {
    private let item: NSStatusItem
    private let onAction: (StatusMenuAction) -> Void

    public init(onAction: @escaping (StatusMenuAction) -> Void) {
        self.onAction = onAction
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                    accessibilityDescription: "4elka")
        item.menu = NSMenu()
    }

    public func refresh(panel: PanelState, launchesAtLogin: Bool) {
        let menu = NSMenu()
        for action in StatusMenu.items(panel: panel) {
            let entry = NSMenuItem(
                title: StatusMenu.title(for: action, launchesAtLogin: launchesAtLogin),
                action: #selector(handle(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = action
            if action == .quit { menu.addItem(.separator()) }
            menu.addItem(entry)
        }
        item.menu = menu
    }

    @objc private func handle(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? StatusMenuAction else { return }
        onAction(action)
    }
}
