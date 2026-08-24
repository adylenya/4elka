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

    /// Фигура закреплена у ВЕРХА экрана и расширяет челку в стороны и вниз,
    /// чтобы та перестала быть заметной. Ниже челки смещается только
    /// содержимое — этим занимается `inPanel`.
    ///
    /// Раньше здесь верх карточки совпадал с низом челки. Это было ошибкой:
    /// карточка выглядела отдельной плашкой, а челка оставалась видна.
    public static func cardFrame(size: CGSize, geometry: NotchGeometry) -> CGRect {
        // Крылья обязаны существовать всегда: в них живёт короткое, и без них
        // фигура не расширяет челку, а просто висит под ней.
        let minWidth = geometry.rect.width + Config.Notch.wingWidth * 2
        let width = max(size.width, minWidth)
        let height = max(size.height,
                         geometry.rect.height + Config.Notch.minFigureOvershoot)
        return CGRect(x: geometry.rect.midX - width / 2,
                      y: geometry.rect.maxY - height,
                      width: width,
                      height: height)
    }

    /// Высота фигуры под содержимое заданной высоты. Содержимое живёт ПОД
    /// челкой, поэтому её высоту надо прибавить, а не надеяться, что содержимое
    /// уместится в общую высоту: замерено на живом экране — фигура 54 точки при
    /// челке 38 оставляла содержимому 16, и вторая строка карточки обрезалась.
    public static func cardHeight(contentHeight: CGFloat, geometry: NotchGeometry) -> CGFloat {
        contentHeight + (geometry.hasPhysicalNotch ? geometry.rect.height : 0)
    }

    /// Насколько стекло раскрытой панели отступает от верха окна. Отступ
    /// меньше высоты планки на её собственное скругление — так скруглённый
    /// угол стекла прячется ЗА планкой, а не торчит прозрачной прорехой рядом.
    public static func glassInset(geometry: NotchGeometry) -> CGFloat {
        guard geometry.hasPhysicalNotch else { return 0 }
        return max(0, geometry.rect.height - Config.Notch.cornerRadius)
    }

    /// Насколько содержимое ВНУТРИ стекла обязано отступить дополнительно —
    /// сверх `glassInset` — чтобы не рисоваться в полосе, которую планка
    /// ещё перекрывает сверху.
    ///
    /// Замерено на живом экране 24.08: `glassInset` уводит стекло вниз ровно
    /// на «высота планки минус её скругление», и это верно для самого стекла
    /// — его скруглённый угол и правда прячется за планкой. Но планка при
    /// этом высотой в полную высоту челки, а не в `glassInset`. Содержимое,
    /// нарисованное от края стекла без добавки, попадает в те самые точки
    /// скругления, которые планка всё ещё закрывает: верх плеера (обложка,
    /// заголовок трека) обрезался её нижним краем.
    ///
    /// `glassInset + glassContentInset` обязана равняться полной высоте
    /// планки — это и проверяет тест, а не глаз.
    public static func glassContentInset(geometry: NotchGeometry) -> CGFloat {
        guard geometry.hasPhysicalNotch else { return 0 }
        return geometry.rect.height - glassInset(geometry: geometry)
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
