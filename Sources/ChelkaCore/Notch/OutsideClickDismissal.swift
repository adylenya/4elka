import Foundation

/// Клик мимо раскрытой панели обязан её закрыть — как у любого выпадающего
/// окна в системе. Решение вынесено чистой функцией отдельно от монитора
/// событий AppKit: последний ничем не проверить тестом, а «внутри рамки или
/// нет» — можно и нужно.
public enum OutsideClickDismissal {
    /// `panelFrame` — `nil`, если панель уже не видна: тогда закрывать нечего.
    public static func shouldDismiss(clickAt point: CGPoint, panelFrame: CGRect?) -> Bool {
        guard let panelFrame else { return false }
        return !panelFrame.contains(point)
    }
}
