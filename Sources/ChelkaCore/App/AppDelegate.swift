import AppKit
import SwiftUI

@MainActor
public final class ChelkaAppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var trigger: TriggerZone?
    private var machine = PanelStateMachine()
    private var geometry = NotchGeometry(rect: .zero, hasPhysicalNotch: false)

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        geometry = NotchGeometry.current(screen: screen)

        let panel = NotchPanel(geometry: geometry)
        // Проба: стекло с семантическим текстом внутри. Своих цветов не заводим —
        // тема системная, и переключение светлая/тёмная должно достаться бесплатно.
        panel.contentView = NSHostingView(rootView: GlassPanel {
            Text("4elka").foregroundStyle(.primary).padding(8)
        })
        panel.orderFrontRegardless()
        self.panel = panel

        trigger = TriggerZone(geometry: geometry,
                              onHover: { [weak self] inside in self?.apply { $0.hovering(inside) } },
                              onClick: { [weak self] in self?.apply { $0.clicked() } })
    }

    private func apply(_ transition: (PanelStateMachine) -> PanelStateMachine) {
        machine = transition(machine)
        guard let panel else { return }
        switch machine.state {
        case .hidden:
            // Панель убирается совсем, а не сжимается в полоску. Сжатая полоска
            // оставалась клавиатурным окном: нажатия пользователя улетали в
            // невидимую щель вместо его приложения.
            panel.orderOut(nil)
        case .peek, .activity:
            panel.resize(to: geometry.rect.size, geometry: geometry)
            panel.orderFrontRegardless()
        case .expanded:
            panel.resize(to: Config.Notch.expandedSize, geometry: geometry)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
        // Зона-триггер молчит, пока панель раскрыта, чтобы не воровать у неё мышь.
        trigger?.setInteractive(machine.state != .expanded)
    }
}
