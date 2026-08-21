import AppKit
import SwiftUI

/// Плитка одного элемента истории: миниатюра для картинки, первые строки для
/// текста, иконка и имя для файлов. Выделенная обведена рамкой цветом акцента,
/// закреплённая помечена скрепкой.
///
/// Тема только системная: здесь используются исключительно семантические цвета
/// (`.primary`, `.secondary`, `.quaternary`, `Color.accentColor`), своих палитр
/// нет и переключение светлая/тёмная достаётся бесплатно.
///
/// Вьюха тонкая и тестами не покрывается — вся логика отбора живёт
/// в `HistorySearch`, а имена файлов в `ClipboardCoordinator.dragName`.
public struct ItemTileView: View {
    private let item: ClipItem
    private let blobs: BlobStore
    private let isSelected: Bool

    public init(item: ClipItem, blobs: BlobStore, isSelected: Bool) {
        self.item = item
        self.blobs = blobs
        self.isSelected = isSelected
    }

    public var body: some View {
        content
            .frame(width: Config.HistoryGrid.tileSide, height: Config.HistoryGrid.tileSide)
            .background(.quaternary)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isSelected ? Color.accentColor : .clear,
                                   lineWidth: Config.HistoryGrid.selectionLineWidth)
            }
            .overlay(alignment: .topTrailing) { pinMark }
            .help(tooltip)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Config.HistoryGrid.tileCornerRadius)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text(let text): textTile(text)
        case .image(let ref): imageTile(ref)
        case .files(let urls): filesTile(urls)
        }
    }

    private func textTile(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(Config.HistoryGrid.textLineLimit)
            .multilineTextAlignment(.leading)
            .padding(Config.HistoryGrid.innerSpacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Блоб мог исчезнуть с диска между чтением индекса и отрисовкой — тогда
    /// вместо миниатюры значок, а не пустая плитка, выглядящая как поломка.
    @ViewBuilder
    private func imageTile(_ ref: ClipItem.ImageRef) -> some View {
        if let image = NSImage(contentsOf: blobs.url(for: ref.blobName)) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder("photo")
        }
    }

    /// Пустой список файлов из битого индекса на диске обращения по нулевому
    /// индексу не заслуживает: показываем значок, а не падаем.
    @ViewBuilder
    private func filesTile(_ urls: [URL]) -> some View {
        if let first = urls.first {
            VStack(spacing: Config.HistoryGrid.innerSpacing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                    .resizable()
                    .frame(width: Config.HistoryGrid.fileIconSide,
                           height: Config.HistoryGrid.fileIconSide)
                Text(caption(for: urls))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(Config.HistoryGrid.innerSpacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder("doc")
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pinMark: some View {
        if item.isPinned {
            Image(systemName: "pin.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(Config.HistoryGrid.innerSpacing)
        }
    }

    private func caption(for urls: [URL]) -> String {
        urls.count == 1 ? (urls.first?.lastPathComponent ?? "") : "файлов: \(urls.count)"
    }

    /// Плитка мелкая, и текст на ней обрезан. Полное содержимое человек
    /// достаёт наведением, а не открытием отдельного окна.
    private var tooltip: String {
        switch item.kind {
        case .text(let text): return text
        case .image(let ref):
            return "\(Int(ref.pixelSize.width)) × \(Int(ref.pixelSize.height))"
        case .files(let urls): return urls.map(\.lastPathComponent).joined(separator: "\n")
        }
    }
}
