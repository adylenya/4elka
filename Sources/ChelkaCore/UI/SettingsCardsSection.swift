import SwiftUI

/// Карточки: сколько живёт выезжающая карточка и от кого её вообще ждать.
/// Выключенный источник отбрасывается на входе очереди — не «показывается
/// пореже», а не показывается вовсе.
struct CardsSettingsSection: View {
    @ObservedObject var controller: SettingsController

    var body: some View {
        Section("Карточки") {
            SecondsRow(title: "Живёт",
                       hint: "Сколько карточка висит под челкой",
                       range: Config.Limits.activityDuration,
                       value: controller.binding(\.activityDuration))
            Toggle("О смене трека", isOn: controller.binding(\.cardsFromTrack))
            Toggle("О копировании", isOn: controller.binding(\.cardsFromClipboard))
            Toggle("О заряде", isOn: controller.binding(\.cardsFromBattery))
        }
    }
}

/// Заряд: пороги, гистерезис и айфон.
struct BatterySettingsSection: View {
    @ObservedObject var controller: SettingsController

    var body: some View {
        Section("Заряд") {
            NumberRow(title: "Нижний порог, %",
                      hint: "Ниже — карточка «заряд на исходе»",
                      range: Config.Limits.batteryLow,
                      value: controller.binding(\.batteryLow))
            NumberRow(title: "Верхний порог, %",
                      hint: "При зарядке выше — карточка «можно отключать»",
                      range: Config.Limits.batteryHigh,
                      value: controller.binding(\.batteryHigh))
            NumberRow(title: "Гистерезис, п. п.",
                      hint: "Насколько заряд должен отойти от порога, чтобы " +
                            "карточка про него могла выехать снова",
                      range: Config.Limits.hysteresis,
                      value: controller.binding(\.batteryHysteresis))
            Toggle("Показывать айфон", isOn: controller.binding(\.showsPhone))
            Text("Айфон отдаёт заряд только по кабелю и только если установлен " +
                 "ideviceinfo. Разрешений приложение не просит.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
