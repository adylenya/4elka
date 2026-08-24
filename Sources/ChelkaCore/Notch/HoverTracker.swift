/// Наведён ли курсор хоть на одну из отслеживаемых зон.
///
/// Зачем отдельный тип. Наведение на челку раскрывает тонкую подсказку, но
/// зона-триггер отслеживает только саму челку (220×38 точек) — а панель под
/// ней шире и продолжается ниже. Курсор, двигаясь от челки дальше в панель,
/// на мгновение выходит за пределы зоны-триггера, и панель схлопывалась в тот
/// же момент — раньше, чем курсор успевал дойти до самой панели. Владелец
/// увидел это и попросил: должно работать как дропдаун — оставаться открытым,
/// пока курсор внутри любой из зон, и закрываться только когда он вышел из
/// обеих. Отсюда набор именованных зон, а не один флаг: зона-триггер и
/// содержимое панели сообщают о себе раздельно, и надёжен именно их союз, а
/// не последнее сообщение от одной из них.
public struct HoverTracker: Equatable, Sendable {
    private let regions: Set<String>

    public init(regions: Set<String> = []) {
        self.regions = regions
    }

    public func entering(_ region: String) -> HoverTracker {
        HoverTracker(regions: regions.union([region]))
    }

    public func leaving(_ region: String) -> HoverTracker {
        HoverTracker(regions: regions.subtracting([region]))
    }

    public var isHoveringAnything: Bool { !regions.isEmpty }
}
