import SwiftUI

/// Заряды устройств в нижней полосе панели: мак, наушники, айфон по кабелю.
/// Тема только системная — используются исключительно семантические цвета
/// (`.primary`, `.secondary`, `Color.accentColor`).
///
/// Список пуст (опрос ещё не прошёл или устройств нет) — строка-заглушка, а не
/// исчезающий раздел: раздел, пропадающий при каждом обновлении данных, дёргал
/// бы раскладку раз в минуту.
///
/// Айфон показывается или нет по настройке — отбор идёт через `DeviceList`, тот
/// же, которым отбираются устройства для карточек: два независимых решения
/// однажды показали бы в списке то, о чём карточки молчат.
///
/// Вьюха тонкая и тестами не покрывается: отбор проверяется в `DeviceList`,
/// разбор замеров — в `MacBatteryParser` и `BluetoothParser`.
public struct DevicesView: View {
    @ObservedObject private var provider: DevicesProvider
    private let showsPhone: () -> Bool

    public init(provider: DevicesProvider, showsPhone: @escaping () -> Bool) {
        self.provider = provider
        self.showsPhone = showsPhone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Config.Panel.rowSpacing) {
            let devices = DeviceList.visible(provider.devices, showsPhone: showsPhone())
            if devices.isEmpty {
                Text(PanelPlaceholder.devices)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices) { DeviceRowView(device: $0) }
            }
        }
    }
}

/// Строка одного устройства: значок, имя, проценты. Заряжающееся помечено
/// молнией цветом акцента — значком, а не цветом самих процентов: цвет как
/// единственный признак не читается на глаз и пропадает в чёрно-белом режиме.
private struct DeviceRowView: View {
    let device: DeviceCharge

    var body: some View {
        HStack(spacing: Config.HistoryGrid.innerSpacing) {
            Image(systemName: device.symbol)
                .foregroundStyle(.primary)
                .frame(width: Config.Panel.deviceSymbolWidth, alignment: .leading)
            Text(device.name)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Config.HistoryGrid.innerSpacing)
            if device.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
            Text("\(device.percent)%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .help(device.isCharging ? "\(device.name): \(device.percent)%, заряжается"
                                : "\(device.name): \(device.percent)%")
    }
}
