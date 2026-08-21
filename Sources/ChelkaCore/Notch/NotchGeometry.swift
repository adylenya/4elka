import AppKit

/// Прямоугольник челки в координатах экрана. Чистый расчёт: не трогает NSScreen,
/// чтобы его можно было проверить тестом без физического дисплея.
public struct NotchGeometry: Equatable {
    public let rect: CGRect
    public let hasPhysicalNotch: Bool

    public static func compute(screenFrame: CGRect,
                               safeAreaTop: CGFloat,
                               auxLeft: CGRect?,
                               auxRight: CGRect?) -> NotchGeometry {
        guard let left = auxLeft, let right = auxRight, safeAreaTop > 0 else {
            return fallback(screenFrame: screenFrame)
        }
        let width = right.minX - left.maxX
        guard width > 0 else { return fallback(screenFrame: screenFrame) }
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
                auxRight: screen.auxiliaryTopRightArea)
    }

    private static func fallback(screenFrame: CGRect) -> NotchGeometry {
        let w = Config.Notch.fallbackWidth
        let h = Config.Notch.fallbackHeight
        let rect = CGRect(x: screenFrame.midX - w / 2,
                         y: screenFrame.maxY - h,
                         width: w, height: h)
        return NotchGeometry(rect: rect, hasPhysicalNotch: false)
    }
}
