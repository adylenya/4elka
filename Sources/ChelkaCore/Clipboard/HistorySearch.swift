import Foundation

/// Вкладки панели истории. `Sendable`, потому что тесты и вьюхи держат её
/// в значениях, живущих вне главного актора.
public enum HistoryTab: String, CaseIterable, Sendable {
    case all, images, files

    public var title: String {
        switch self {
        case .all: return "Буфер"
        case .images: return "Скриншоты"
        case .files: return "Файлы"   // не «Полка»: полка файлов — это Task 22, другое хранилище
        }
    }
}

/// Отбор элементов истории по вкладке и строке поиска. Чистая функция —
/// проверяется тестом, а не глазами по панели.
public enum HistorySearch {
    public static func filter(_ items: [ClipItem], tab: HistoryTab, query: String) -> [ClipItem] {
        let byTab = items.filter { item in
            switch tab {
            case .all: return true
            case .images: return item.isImage
            case .files: return item.isFiles
            }
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return byTab }
        return byTab.filter { matches($0, needle) }
    }

    /// Регистр и диакритика не должны мешать: человек ищет «елка», а копировал
    /// «Ёлка». Картинка без текста не совпадает ни с чем — имя блоба служебное,
    /// и совпадение по нему выглядело бы как случайный мусор в выдаче.
    private static func matches(_ item: ClipItem, _ needle: String) -> Bool {
        let haystack: String
        switch item.kind {
        case .text(let s): haystack = s
        case .files(let urls): haystack = urls.map(\.lastPathComponent).joined(separator: " ")
        case .image: return false
        }
        return haystack.range(of: needle,
                              options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
