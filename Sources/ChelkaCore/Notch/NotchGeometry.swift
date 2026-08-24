import AppKit

/// Прямоугольник челки в координатах экрана. Чистый расчёт: не трогает NSScreen,
/// чтобы его можно было проверить тестом без физического дисплея.
public struct NotchGeometry: Equatable, Sendable {
    public let rect: CGRect
    public let hasPhysicalNotch: Bool

    /// Геометрия, когда экранов нет вовсе. Панель ставить некуда, но приложение
    /// обязано остаться живым: иконка в строке меню создаётся раньше и
    /// безусловно, а геометрия пересчитается по уведомлению о смене экранов.
    public static let none = NotchGeometry(rect: .zero, hasPhysicalNotch: false)

    /// Есть ли куда ставить окна. Пустой прямоугольник — это «экрана нет»:
    /// панель не показывается, зона-триггер не принимает мышь, иначе невидимое
    /// окно, съедающее нажатия, встаёт где-то в строке меню.
    public var isUsable: Bool { !rect.isEmpty }

    public init(rect: CGRect, hasPhysicalNotch: Bool) {
        self.rect = rect
        self.hasPhysicalNotch = hasPhysicalNotch
    }

    /// `menuBarHeight` нужен только запасной геометрии: на экране без выреза
    /// плашка обязана начинаться ПОД строкой меню. Иначе окно уровнем выше
    /// строки меню накрывает её, и клик по заголовку меню открывает панель
    /// вместо самого меню.
    public static func compute(screenFrame: CGRect,
                               safeAreaTop: CGFloat,
                               auxLeft: CGRect?,
                               auxRight: CGRect?,
                               menuBarHeight: CGFloat) -> NotchGeometry {
        guard let left = auxLeft, let right = auxRight, safeAreaTop > 0 else {
            return fallback(screenFrame: screenFrame, menuBarHeight: menuBarHeight)
        }
        let width = right.minX - left.maxX
        guard width > 0 else {
            return fallback(screenFrame: screenFrame, menuBarHeight: menuBarHeight)
        }
        let rect = CGRect(x: left.maxX,
                         y: screenFrame.maxY - safeAreaTop,
                         width: width,
                         height: safeAreaTop)
        return NotchGeometry(rect: rect, hasPhysicalNotch: true)
    }

    public static func current(screen: NSScreen) -> NotchGeometry {
        compute(screenFrame: screen.frame,
                safeAreaTop: screen.safeAreaInsets.top,
                auxLeft: screen.auxiliaryTopLeftArea,
                auxRight: screen.auxiliaryTopRightArea,
                // Дока сверху не бывает, поэтому разница по верхнему краю —
                // это ровно строка меню.
                menuBarHeight: max(0, screen.frame.maxY - screen.visibleFrame.maxY))
    }

    private static func fallback(screenFrame: CGRect, menuBarHeight: CGFloat) -> NotchGeometry {
        let w = Config.Notch.fallbackWidth
        let h = Config.Notch.fallbackHeight
        let rect = CGRect(x: screenFrame.midX - w / 2,
                         y: screenFrame.maxY - menuBarHeight - h,
                         width: w, height: h)
        return NotchGeometry(rect: rect, hasPhysicalNotch: false)
    }
}
