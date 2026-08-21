import SwiftUI

/// Текущая погода для нижней полосы панели: символ и градусы из снимка
/// `WeatherProvider`. Тема только системная — используются исключительно
/// семантические цвета (`.primary`, `.secondary`).
///
/// Если снимка нет вовсе (ни сети, ни кэша на диске) — прочерк, а не ноль:
/// ноль выглядел бы как настоящая температура. Если снимок старше часа,
/// рядом мелким шрифтом дописывается время наблюдения, чтобы не выдать
/// вчерашнюю погоду за сегодняшнюю.
///
/// Вьюха тонкая и не покрывается тестами — вся логика живёт в
/// `WeatherSnapshot` и `WeatherProvider`.
public struct WeatherView: View {
    @ObservedObject private var provider: WeatherProvider

    private static let staleAfter: TimeInterval = 60 * 60

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
                if isStale(snapshot) {
                    Text(Self.observedAtString(snapshot.observedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func isStale(_ snapshot: WeatherSnapshot) -> Bool {
        Date().timeIntervalSince(snapshot.observedAt) > Self.staleAfter
    }

    private static func observedAtString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: Config.timezone)
        return formatter.string(from: date)
    }
}
