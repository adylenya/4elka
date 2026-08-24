import Foundation

/// Какие заряды показывать. Чистая функция: айфон по кабелю человек может
/// выключить в настройках, а решать это внутри вьюхи и внутри правил
/// уведомлений по отдельности — значит однажды показать в списке то, о чём
/// уведомления молчат.
public enum DeviceList {
    /// Порядок сохраняется: мак первым, дальше блютус, дальше айфон — так их
    /// складывает опрос, и переставлять их в отрисовке незачем.
    public static func visible(_ devices: [DeviceCharge], showsPhone: Bool) -> [DeviceCharge] {
        guard !showsPhone else { return devices }
        return devices.filter { $0.source != .phone }
    }
}
