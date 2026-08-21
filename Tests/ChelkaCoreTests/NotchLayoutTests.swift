import Testing
import AppKit
@testable import ChelkaCore

// Свойство, а не глобальная константа: `NotchGeometry` не Sendable (это тип
// Task 2, не в объёме этой задачи), а глобальный `let` такого типа не
// проходит проверку конкурентности Swift 6. Вычисляемое свойство не хранит
// общего состояния и эту проверку не запускает.
private var measured: NotchGeometry {
    NotchGeometry(rect: CGRect(x: 918, y: 1291, width: 220, height: 38), hasPhysicalNotch: true)
}

@Test func cardStartsBelowTheNotchNotBehindIt() {
    // Раньше верх карточки совпадал с верхом экрана, и первая строка уезжала
    // за челку. Теперь верх карточки — это низ челки.
    let frame = NotchLayout.cardFrame(size: CGSize(width: 320, height: 54), geometry: measured)
    #expect(frame.maxY == measured.rect.minY)
    #expect(frame.midX == measured.rect.midX)
    #expect(frame.height == 54)
}

@Test func panelBodyStartsBelowTheNotch() {
    let layout = NotchLayout.inPanel(size: Config.Notch.expandedSize, geometry: measured)
    // Тело занимает всё, кроме верхней полосы высотой челки.
    #expect(layout.body.height == Config.Notch.expandedSize.height - measured.rect.height)
    #expect(layout.body.minY == 0)
    #expect(layout.body.width == Config.Notch.expandedSize.width)
}

@Test func stripsSitBesideTheNotchAndNeverUnderIt() {
    let size = Config.Notch.expandedSize
    let layout = NotchLayout.inPanel(size: size, geometry: measured)
    // Полосы в верхних 38 точках, слева и справа от челки, и не пересекают её.
    #expect(layout.leftStrip.height == measured.rect.height)
    #expect(layout.rightStrip.height == measured.rect.height)
    #expect(layout.leftStrip.maxY == size.height)
    let notchInPanel = (size.width - measured.rect.width) / 2
    #expect(abs(layout.leftStrip.width - notchInPanel) < 0.001)
    #expect(abs(layout.rightStrip.width - notchInPanel) < 0.001)
    #expect(layout.leftStrip.maxX <= layout.rightStrip.minX)
}

@Test func stripsAreEmptyWhenPanelIsNarrowerThanTheNotch() {
    let narrow = CGSize(width: 120, height: 200)
    let layout = NotchLayout.inPanel(size: narrow, geometry: measured)
    #expect(layout.leftStrip.width == 0)
    #expect(layout.rightStrip.width == 0)
    // Тело при этом всё равно есть.
    #expect(layout.body.height > 0)
}

@Test func withoutPhysicalNotchThereIsNoStripAndBodyIsWhole() {
    let plain = NotchGeometry(rect: CGRect(x: 850, y: 1048, width: 220, height: 32),
                              hasPhysicalNotch: false)
    let layout = NotchLayout.inPanel(size: Config.Notch.expandedSize, geometry: plain)
    #expect(layout.leftStrip.isEmpty)
    #expect(layout.rightStrip.isEmpty)
    #expect(layout.body.height == Config.Notch.expandedSize.height)
}

@Test func panelTakesKeyboardOnlyWhenExpanded() {
    // Карточка перехватывала набор текста, потому что окну разрешалось
    // становиться клавиатурным всегда.
    for state in [PanelState.hidden, .peek, .activity] {
        #expect(!NotchPanel.allowsKeyboard(in: state))
    }
    #expect(NotchPanel.allowsKeyboard(in: .expanded))
}
