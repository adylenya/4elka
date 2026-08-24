import SwiftUI

/// Погода для нижней полосы панели: город, текущая температура и несколько
/// часов вперёд. Тема только системная — используются исключительно
/// семантические цвета (`.primary`, `.secondary`).
///
/// Если снимка нет вовсе (ни сети, ни кэша на диске) — строка «погода
/// недоступна», а не ноль и не пустое место: ноль выглядел бы как настоящая
/// температура, а исчезающий раздел дёргал бы раскладку при каждом обновлении.
/// Если снимок устарел, рядом мелким шрифтом дописывается возраст данных
/// человеческими словами (`ageDescription`) — не время наблюдения: «14:32» у
/// трёхдневной погоды читается как сегодняшняя, а «3 дн назад» — нет. Порог
/// устаревания берётся из настроек, а не из `Config`.
///
/// Вьюха тонкая и не покрывается тестами — вся логика живёт в
/// `WeatherSnapshot` и `WeatherProvider`.
public struct WeatherView: View {
    @ObservedObject private var provider: WeatherProvider
    private let city: () -> String

    public init(provider: WeatherProvider, city: @escaping () -> String) {
        self.provider = provider
        self.city = city
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let snapshot = provider.snapshot {
                current(snapshot)
                if !snapshot.upcoming.isEmpty {
                    upcoming(snapshot.upcoming)
                }
            } else {
                Text(PanelPlaceholder.weather)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Место в нижней полосе есть — вправо от календаря места хватает и
        // на погоду, и на заряды, но без этого вьюха занимала только свою
        // собственную минимальную ширину, а справа оставалась пустота.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func current(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.symbol)
                .font(.system(size: Config.Panel.weatherIconSize))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 0) {
                Text(city())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(snapshot.summary)
                    .font(.system(size: Config.Panel.weatherTemperatureSize, weight: .medium))
                    .foregroundStyle(.primary)
                if let age = snapshot.ageDescription(now: Date(),
                                                     staleAfter: provider.current.staleAfter) {
                    Text(age)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Ряд из нескольких карточек-часов. Число часов решает
    /// `Config.Weather.forecastHours` на стороне запроса — вьюха просто
    /// рисует то, что пришло, и не считает, сколько показывать.
    private func upcoming(_ hours: [WeatherSnapshot.HourlyForecast]) -> some View {
        // Каждый час — равная доля доступной ширины, а не кучка слева с
        // пустотой справа: ряд обязан растянуться на всю строку, как ряды
        // календаря рядом с ним.
        HStack(spacing: 0) {
            ForEach(hours, id: \.hour) { point in
                VStack(spacing: 1) {
                    Text(point.hour)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: WeatherSnapshot.symbol(forCode: point.code))
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Text("\(Int(point.celsius.rounded()))°")
                        .font(.caption2)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
