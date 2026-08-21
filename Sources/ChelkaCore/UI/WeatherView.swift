import SwiftUI

/// Текущая погода для нижней полосы панели: символ и градусы из снимка
/// `WeatherProvider`. Тема только системная — используются исключительно
/// семантические цвета (`.primary`, `.secondary`).
///
/// Если снимка нет вовсе (ни сети, ни кэша на диске) — прочерк, а не ноль:
/// ноль выглядел бы как настоящая температура. Если снимок устарел, рядом
/// мелким шрифтом дописывается возраст данных человеческими словами
/// (`ageDescription`) — не время наблюдения: «14:32» у трёхдневной погоды
/// читается как сегодняшняя, а «3 дн назад» — нет.
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
                if let age = snapshot.ageDescription(now: Date()) {
                    Text(age)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
