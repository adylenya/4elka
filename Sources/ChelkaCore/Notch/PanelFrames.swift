import AppKit

/// Рамки окна панели для всех четырёх состояний — одна чистая функция вместо
/// приватного `switch` внутри делегата.
///
/// Зачем отдельный тип. Раньше карточка считала свою рамку через
/// `NotchLayout.cardFrame`, а наведение и раскрытие звали изменение размера с
/// плоским числом. Пути разошлись, и гарантии «крылья по бокам» и «содержимое
/// живёт ПОД челкой» достались только карточке: наведение получало размером
/// ровно вырез (тело нулевой высоты — состояние не показывало ничего), а
/// раскрытая панель получала `expandedSize` как полную высоту, из которой
/// вырез съедал 38 точек. Одно и то же расхождение стоило трёх дефектов,
/// поэтому расчёт вынесен в проверяемый тестом слой.
///
/// Все состояния выражены через «размер содержимого плюс высота челки».
public enum PanelFrames {
    /// Размер содержимого — того, что лежит ПОД челкой. `nil` — окна на экране
    /// нет вовсе.
    public static func contentSize(for state: PanelState,
                                   geometry: NotchGeometry) -> CGSize? {
        switch state {
        case .hidden:
            return nil
        case .peek:
            // Тонкая подсказка, выезжающая из-под челки. Ширину даёт сама
            // челка, крылья добавит `NotchLayout.cardFrame`.
            return CGSize(width: geometry.rect.width,
                          height: Config.Notch.peekBodyHeight)
        case .activity:
            return CGSize(width: max(geometry.rect.width + Config.Activity.cardExtraWidth,
                                     Config.Activity.cardMinWidth),
                          height: Config.Activity.cardBodyHeight)
        case .expanded:
            return Config.Notch.expandedSize
        }
    }

    /// Рамка окна в координатах экрана. `nil` — окно надо убрать: либо
    /// состояние скрытое, либо экрана нет вовсе.
    public static func frame(for state: PanelState, geometry: NotchGeometry) -> CGRect? {
        guard geometry.isUsable,
              let content = contentSize(for: state, geometry: geometry) else { return nil }
        let height = NotchLayout.cardHeight(contentHeight: content.height, geometry: geometry)
        return NotchLayout.cardFrame(size: CGSize(width: content.width, height: height),
                                     geometry: geometry)
    }

    /// Раскладка внутри окна этого состояния: полосы по бокам челки и тело
    /// под ней. Содержимое обязано считать своё место отсюда, а не из размера
    /// окна целиком.
    public static func layout(for state: PanelState, geometry: NotchGeometry) -> NotchLayout? {
        guard let frame = frame(for: state, geometry: geometry) else { return nil }
        return NotchLayout.inPanel(size: frame.size, geometry: geometry)
    }
}
