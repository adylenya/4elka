import SwiftUI

/// Плеер в раскрытой панели: обложка, название/исполнитель, полоса позиции,
/// три кнопки управления. Тема только системная — здесь используются
/// исключительно семантические цвета (`.primary`, `.secondary`,
/// `Color.accentColor`), кнопки — системный стиль `.glass`.
///
/// Обложка приходит уже декодированной из `MediaCoordinator.artwork`: он сам
/// решает, когда её декодировать (один раз на трек), вьюха только показывает
/// готовую картинку и не трогает `NSImage(data:)`.
///
/// Живая позиция не хранится ни здесь, ни в координаторе — `NowPlaying.position(at:)`
/// считает её из опорной точки на момент отрисовки. Полосу двигает таймер
/// отображения (`TimelineView`), а не отдельное состояние, которое пришлось бы
/// пересчитывать и публиковать самому.
///
/// Если источник недоступен или ничего не играет — строка «ничего не играет»,
/// а не пустое место: пустота выглядит как поломка.
public struct PlayerView: View {
    @ObservedObject private var coordinator: MediaCoordinator

    public init(coordinator: MediaCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Group {
            if coordinator.isAvailable, !coordinator.state.isEmpty {
                player
            } else {
                Text("ничего не играет")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var player: some View {
        TimelineView(.periodic(from: .now, by: Config.Media.positionTickInterval)) { timeline in
            HStack(spacing: 12) {
                artworkView
                VStack(alignment: .leading, spacing: 4) {
                    Text(coordinator.state.title ?? "")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let artist = coordinator.state.artist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    positionBar(at: timeline.date)
                }
                controls
            }
        }
    }

    private var artworkView: some View {
        Group {
            if let image = coordinator.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
            }
        }
        .frame(width: Config.Media.artworkSide, height: Config.Media.artworkSide)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Длительность трека не всегда известна — тогда полоса рисуется пустой
    /// (не гадаем долю от неизвестного целого), а вместо второй метки времени
    /// показывается прочерк, а не ноль или обман про 100%.
    private func positionBar(at now: Date) -> some View {
        let position = coordinator.state.position(at: now) ?? 0
        // Отсутствующая или нулевая длительность — не повод гадать долю от
        // неизвестного целого: полоса рисуется пустой, а не наугад.
        let duration = coordinator.state.duration.flatMap { $0 > 0 ? $0 : nil }
        return VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: duration != nil ? position : 0, total: duration ?? 1)
                .tint(.accentColor)
            HStack {
                Text(Self.formatted(position))
                Spacer()
                Text(duration.map(Self.formatted) ?? "--:--")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: { coordinator.send(.previous) }) {
                Image(systemName: "backward.fill")
            }
            Button(action: { coordinator.send(.toggle) }) {
                Image(systemName: coordinator.state.isPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: { coordinator.send(.next) }) {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.glass)
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
