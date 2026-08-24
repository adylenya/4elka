import SwiftUI

/// Текущая погода для нижней полосы панели: символ и градусы из снимка
/// `WeatherProvider`. Тема только системная — используются исключительно
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

    public init(provider: WeatherProvider) {
        self.provider = provider
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let snapshot = provider.snapshot {
                Image(systemName: snapshot.symbol)
                    .foregroundStyle(.primary)
                Text(snapshot.summary)
                    .foregroundStyle(.primary)
                if let age = snapshot.ageDescription(now: Date(),
                                                     staleAfter: provider.current.staleAfter) {
                    Text(age)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(PanelPlaceholder.weather)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
