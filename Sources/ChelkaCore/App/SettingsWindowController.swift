import AppKit
import SwiftUI

/// Окно настроек — обычное окно с заголовком, а не панель над челкой:
/// закрывается как любое другое, переносится на другой рабочий стол, живёт
/// в списке окон.
///
/// Окно ровно одно. Повторный вызов пункта меню поднимает существующее, а не
/// открывает второе: два окна настроек писали бы в один файл, и последнее
/// закрытое затирало бы правки первого.
@MainActor
public final class SettingsWindowController {
    private let controller: SettingsController
    private let actions: SettingsActions
    private var window: NSWindow?

    public init(controller: SettingsController, actions: SettingsActions) {
        self.controller = controller
        self.actions = actions
    }

    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        // Приложение живёт без иконки в доке (политика `.accessory`), и без
        // этого вызова окно вышло бы за спиной активного приложения.
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Config.SettingsWindow.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Настройки 4elka"
        // Закрытие окна не должно его освобождать: ссылку мы держим сами, и
        // повторное открытие обязано поднять то же окно, а не обратиться к
        // освобождённой памяти.
        window.isReleasedWhenClosed = false
        window.contentMinSize = Config.SettingsWindow.minSize
        window.contentView = NSHostingView(
            rootView: SettingsView(controller: controller, actions: actions))
        window.center()
        return window
    }
}
