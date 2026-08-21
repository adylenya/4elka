import AppKit

/// Челка непрозрачна, и раскладка обходит её. Чистая функция: проверяется тестом,
/// а не глазами.
public struct NotchLayout: Equatable, Sendable {
    /// Полоса слева от челки в верхних `notchHeight` точках. Пустая, если места нет.
    public let leftStrip: CGRect
    /// Полоса справа от челки.
    public let rightStrip: CGRect
    /// Всё, что ниже челки — основное место панели.
    public let body: CGRect

    /// Верх карточки — это низ челки, а не верх экрана. Иначе первая строка
    /// карточки физически прячется за челкой.
    public static func cardFrame(size: CGSize, geometry: NotchGeometry) -> CGRect {
        CGRect(x: geometry.rect.midX - size.width / 2,
               y: geometry.rect.minY - size.height,
               width: size.width,
               height: size.height)
    }

    /// Координаты внутри панели: начало слева снизу, как в AppKit.
    public static func inPanel(size: CGSize, geometry: NotchGeometry) -> NotchLayout {
        guard geometry.hasPhysicalNotch else {
            return NotchLayout(leftStrip: .zero, rightStrip: .zero,
                               body: CGRect(origin: .zero, size: size))
        }
        let stripHeight = min(geometry.rect.height, size.height)
        let sideWidth = max(0, (size.width - geometry.rect.width) / 2)
        let stripY = size.height - stripHeight
        return NotchLayout(
            leftStrip: CGRect(x: 0, y: stripY, width: sideWidth, height: stripHeight),
            rightStrip: CGRect(x: size.width - sideWidth, y: stripY,
                               width: sideWidth, height: stripHeight),
            body: CGRect(x: 0, y: 0, width: size.width, height: size.height - stripHeight))
    }
}
