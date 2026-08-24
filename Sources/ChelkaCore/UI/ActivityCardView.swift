import SwiftUI

/// Карточка события под челкой.
///
/// Картинка приходит уже прочитанной, а не читается здесь: чтение с диска
/// внутри отрисовки означало бы, что снимок (до сорока мегабайт) перечитывается
/// и раскодируется на каждый проход отрисовки — двенадцать раз за три секунды
/// жизни карточки.
public struct ActivityCardView: View {
    public let event: ActivityEvent
    public let image: NSImage?

    public init(event: ActivityEvent, image: NSImage? = nil) {
        self.event = event
        self.image = image
    }

    public var body: some View {
        HStack(spacing: Config.Activity.cardSpacing) {
            thumbnail
            VStack(alignment: .leading, spacing: Config.Activity.cardTextSpacing) {
                Text(event.title)
                    .font(.system(size: Config.Activity.cardTitleFontSize, weight: .medium))
                    .lineLimit(1)
                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(.system(size: Config.Activity.cardSubtitleFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Config.Activity.cardHorizontalPadding)
        .padding(.vertical, Config.Activity.cardVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(nsImage: image)
                .resizable().scaledToFill()
                .frame(width: Config.Activity.cardThumbnailSide,
                       height: Config.Activity.cardThumbnailSide)
                .clipShape(RoundedRectangle(
                    cornerRadius: Config.Activity.cardThumbnailCornerRadius))
        } else {
            Image(systemName: icon)
                .font(.system(size: Config.Activity.cardIconFontSize))
                .frame(width: Config.Activity.cardThumbnailSide)
        }
    }

    private var icon: String {
        switch event.kind {
        case .track: return "music.note"
        case .clipboard: return "doc.on.clipboard"
        case .battery: return "battery.25"
        }
    }
}
