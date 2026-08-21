import Foundation

/// Выделенные элементы истории. Порядок сохраняется: в нём файлы и попадут
/// в жест перетаскивания, а множество этот порядок потеряло бы.
///
/// Иммутабельна, как и остальное состояние: каждое изменение возвращает
/// новый экземпляр.
public struct Selection: Equatable, Sendable {
    public let ids: [UUID]

    public init(ids: [UUID] = []) { self.ids = ids }

    /// `cmd`-клик: добавляет или убирает один элемент, не трогая остальные.
    public func toggling(_ id: UUID) -> Selection {
        ids.contains(id) ? Selection(ids: ids.filter { $0 != id }) : Selection(ids: ids + [id])
    }

    /// Обычный клик: выделен ровно один элемент, прежнее выделение снято.
    public func replacing(with id: UUID) -> Selection { Selection(ids: [id]) }

    public func cleared() -> Selection { Selection() }

    /// Сужение до того, что человек видит перед собой.
    ///
    /// Без него выделение переживало смену вкладки и строки поиска, а `⌫` и `⌘P`
    /// работали по невидимому: выделив текст на вкладке «Буфер» и картинку на
    /// «Скриншотах», человек нажимал `⌫` и терял обе записи — включая ту, о
    /// которой уже забыл. Отмены у нас нет, поэтому выделение обязано совпадать
    /// с видимым.
    ///
    /// Видимое, но не выделенное, выделением не становится: сужение только
    /// убирает, никогда не добавляет. Порядок выделения сохраняется — в нём
    /// элементы уйдут в перетаскивание.
    public func narrowed(to visibleIDs: [UUID]) -> Selection {
        let visible = Set(visibleIDs)
        return Selection(ids: ids.filter { visible.contains($0) })
    }

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    public var isEmpty: Bool { ids.isEmpty }
}
