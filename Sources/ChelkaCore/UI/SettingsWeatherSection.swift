import SwiftUI

/// Погода: город (вместо ввода чисел), координаты для места, которого в
/// списке нет, интервал обновления и порог устаревания.
struct WeatherSettingsSection: View {
    @ObservedObject var controller: SettingsController
    @State private var query = ""

    var body: some View {
        Section("Погода") {
            LabeledContent("Город") {
                Text(controller.settings.weatherCity.isEmpty
                     ? "координаты вручную"
                     : controller.settings.weatherCity)
                    .foregroundStyle(.secondary)
            }
            citySearch
            CoordinateRow(title: "Широта",
                          range: Config.Limits.latitude,
                          value: coordinate(get: { $0.weatherLatitude },
                                            set: { $0.settingLatitude($1) }))
            CoordinateRow(title: "Долгота",
                          range: Config.Limits.longitude,
                          value: coordinate(get: { $0.weatherLongitude },
                                            set: { $0.settingLongitude($1) }))
            NumberRow(title: "Обновлять, мин",
                      range: Config.Limits.weatherRefreshMinutes,
                      value: controller.binding(\.weatherRefreshMinutes))
            NumberRow(title: "Считать устаревшей через, мин",
                      hint: "Устаревшая погода показывается с пометкой о возрасте, " +
                            "а не прочерком",
                      range: Config.Limits.weatherStaleMinutes,
                      value: controller.binding(\.weatherStaleMinutes))
        }
    }

    /// Поиск по зашитому списку городов: без сети и без разрешения на
    /// геолокацию. Города, которого в списке нет, задаются координатами ниже.
    ///
    /// Прокручиваемый стек, а не `List`: вложенный в `Form` список заводит
    /// вторую полосу прокрутки внутри первой.
    private var citySearch: some View {
        let found = CityCatalog.search(query)
        return VStack(alignment: .leading, spacing: Config.SettingsWindow.rowSpacing) {
            TextField("Найти город", text: $query)
            ScrollView {
                VStack(alignment: .leading, spacing: Config.SettingsWindow.listRowSpacing) {
                    ForEach(found) { city in
                        cityRow(city)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Config.SettingsWindow.listHeight)
            if found.isEmpty {
                Text("Ничего не нашлось — задайте координаты вручную.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Координаты правятся не обычным биндингом на поле: ручная правка обязана
    /// стереть название города, иначе в настройках останется «Астана» с
    /// координатами другого места.
    private func coordinate(get: @escaping (Settings) -> Double,
                            set: @escaping (Settings, Double) -> Settings) -> Binding<Double> {
        Binding(get: { get(controller.settings) },
                set: { value in controller.update { set($0, value) } })
    }

    private func cityRow(_ city: City) -> some View {
        Button {
            controller.update { $0.choosing(city) }
            query = ""
        } label: {
            HStack {
                Text(city.name)
                Spacer()
                if city.name == controller.settings.weatherCity {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
            // Нажатие ловится всей строкой, а не только буквами названия.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Календарь: первый день недели по системе или свой.
struct CalendarSettingsSection: View {
    @ObservedObject var controller: SettingsController

    var body: some View {
        Section("Календарь") {
            Toggle("Первый день недели — по системе",
                   isOn: controller.binding(\.firstWeekdayFollowsSystem))
            Picker("Первый день недели", selection: controller.binding(\.firstWeekday)) {
                ForEach(Config.Limits.firstWeekday, id: \.self) { day in
                    Text(Self.weekdayName(day)).tag(day)
                }
            }
            .disabled(controller.settings.firstWeekdayFollowsSystem)
        }
    }

    /// Названия дней берутся у системы, а не пишутся руками: они обязаны
    /// совпадать с тем, что человек видит в самом календаре.
    private static func weekdayName(_ day: Int) -> String {
        let symbols = DateFormatter().standaloneWeekdaySymbols ?? []
        guard symbols.indices.contains(day - 1) else { return "\(day)" }
        return symbols[day - 1].capitalized
    }
}
