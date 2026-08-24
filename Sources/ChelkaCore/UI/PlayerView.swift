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
/// Если играть нечему — строка вместо пустого места: пустота выглядит как
/// поломка. Строки две и они разные: «плеер недоступен» значит «адаптера нет
/// или он сдался», «ничего не играет» — «плеер жив, музыки нет». Одна строка на
/// оба случая скрывала бы полностью мёртвую подсистему за безобидной надписью,
/// а именно так плеер и прожил свою первую неделю.
public struct PlayerView: View {
    @ObservedObject private var coordinator: MediaCoordinator
    /// Состояние панели нужно ровно за одним: решить, тикать ли полосе позиции.
    private let panel: PanelState

    /// Что показывать — замыканием, а не значением: тумблеры «Показывать
    /// обложку» и «Показывать полосу позиции» человек крутит в отдельном окне, и
    /// снятая при сборке копия отстала бы от него до следующего раскрытия.
    private let options: () -> PlayerOptions

    public init(coordinator: MediaCoordinator, panel: PanelState,
                options: @escaping () -> PlayerOptions) {
        self.coordinator = coordinator
        self.panel = panel
        self.options = options
    }

    /// Тикает полоса позиции или стоит.
    ///
    /// Двигать её надо только когда есть что двигать: на паузе позиция стоит на
    /// месте, при закрытой панели её вообще никто не видит, а выключенную
    /// настройкой полосу двигать тем более незачем. Приложение живёт в челке
    /// целый день, и таймер два раза в секунду впустую — это батарея.
    ///
    /// `nonisolated`, потому что это чистая функция от параметров: `self` она не
    /// трогает, и изоляция вьюхи на главный актор ей не нужна — иначе тест не
    /// смог бы позвать её без него.
    public nonisolated static func shouldTickPosition(isPlaying: Bool, panel: PanelState,
                                                      showsPositionBar: Bool) -> Bool {
        isPlaying && panel == .expanded && showsPositionBar
    }

    public var body: some View {
        Group {
            switch presence {
            case .playing:
                player
            case .unavailable:
                placeholder(PanelPlaceholder.playerUnavailable)
            case .idle:
                placeholder(PanelPlaceholder.playerIdle)
            }
        }
    }

    private var presence: PlayerPresence {
        PlayerPresence.make(isAvailable: coordinator.isAvailable,
                            isEmpty: coordinator.state.isEmpty)
    }

    /// Заглушка занимает то же место, что и сам плеер: раздел не имеет права
    /// схлопываться, иначе всё, что ниже, подпрыгивает при смене трека.
    private func placeholder(_ text: String) -> some View {
        HStack {
            Text(text)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var player: some View {
        Group {
            if Self.shouldTickPosition(isPlaying: coordinator.state.isPlaying, panel: panel,
                                       showsPositionBar: options().showsPositionBar) {
                TimelineView(.periodic(from: .now, by: Config.Media.positionTickInterval)) { timeline in
                    row(at: timeline.date)
                }
            } else {
                // Позиция замерена один раз на отрисовку: стоящую полосу
                // незачем пересобирать, а закрытую — тем более.
                row(at: Date())
            }
        }
    }

    private func row(at now: Date) -> some View {
        HStack(spacing: Config.Media.rowSpacing) {
            // Обложку можно выключить настройкой: место под неё тогда не
            // занимается вовсе, а название с кнопками занимают всю строку.
            if options().showsArtwork { artworkView }
            VStack(alignment: .leading, spacing: Config.Media.textSpacing) {
                // Строки берутся из `displayLines`: пустое название не должно
                // давать пустую первую строку, а исполнитель без названия не
                // должен дублироваться во второй.
                Text(coordinator.state.displayLines?.headline ?? "")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let artist = coordinator.state.displayLines?.subheadline {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if options().showsPositionBar { positionBar(at: now) }
            }
            controls
        }
    }

    private var artworkView: some View {
        Group {
            if let image = coordinator.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: Config.Media.artworkCornerRadius)
                    .fill(.quaternary)
            }
        }
        .frame(width: Config.Media.artworkSide, height: Config.Media.artworkSide)
        .clipShape(RoundedRectangle(cornerRadius: Config.Media.artworkCornerRadius))
    }

    /// Длительность трека не всегда известна — тогда полоса рисуется пустой
    /// (не гадаем долю от неизвестного целого), а вместо второй метки времени
    /// показывается прочерк, а не ноль или обман про 100%.
    private func positionBar(at now: Date) -> some View {
        let position = coordinator.state.position(at: now) ?? 0
        // Отсутствующая или нулевая длительность — не повод гадать долю от
        // неизвестного целого: полоса рисуется пустой, а не наугад.
        let duration = coordinator.state.duration.flatMap { $0 > 0 ? $0 : nil }
        return VStack(alignment: .leading, spacing: Config.Media.positionLabelSpacing) {
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
        HStack(spacing: Config.Media.controlSpacing) {
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
