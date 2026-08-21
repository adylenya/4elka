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

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    public var isEmpty: Bool { ids.isEmpty }
}
