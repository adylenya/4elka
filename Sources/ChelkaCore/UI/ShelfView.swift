import AppKit
import SwiftUI

/// Полоса полки в раскрытой панели: что лежит на полке и что с этим можно
/// сделать — унести мышью или отправить по AirDrop.
///
/// Механика выделения и перетаскивания та же, что у сетки истории: клик
/// приходит из `DragSourceRepresentable`, потому что AppKit-вью поверх плитки
/// съедает `mouseDown` и SwiftUI-жест под ней не сработал бы. Разница одна:
/// на полке обычный клик выделяет, а не копирует в буфер, — копировать здесь
/// нечего, файлы уносят жестом или отправляют кнопкой.
///
/// Ничего не материализуется: файлы уже лежат на диске под своими именами,
/// копия была бы и лишней работой, и вторым файлом там, куда его перетащат.
///
/// Вьюха тонкая и тестами не покрывается: полка проверяется в `ShelfStoreTests`.
public struct ShelfView: View {
    @ObservedObject private var coordinator: ShelfCoordinator
    @State private var selection = Selection()

    public init(coordinator: ShelfCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Config.Shelf.innerSpacing) {
            header
            content
        }
        .frame(height: Config.Shelf.stripHeight)
        // Выделение обязано забывать ушедшие с полки файлы: иначе после
        // выметания пропавших записей кнопки остаются доступными, а нажатие
        // на них ничего не делает.
        .onChange(of: coordinator.shelf) { _, store in
            let alive = Set(store.items.map(\.id))
            selection = Selection(ids: selection.ids.filter(alive.contains))
        }
    }

    private var header: some View {
        HStack(spacing: Config.HistoryGrid.tileSpacing) {
            Text("Полка")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button { coordinator.sendViaAirDrop(selection.ids) } label: {
                Image(systemName: "paperplane")
            }
            .buttonStyle(.glass)
            .disabled(selection.isEmpty)
            .help("Отправить выделенное по AirDrop")

            Button(action: removeSelected) {
                Image(systemName: "trash")
            }
            .buttonStyle(.glass)
            .disabled(selection.isEmpty)
            .help("Убрать выделенное с полки")
        }
    }

    /// Пустая полка — это не поломка, а приглашение: вместо сетки из ничего
    /// показываем зону приёма с подписью.
    @ViewBuilder
    private var content: some View {
        if coordinator.shelf.items.isEmpty {
            emptyShelf
        } else {
            tiles
        }
    }

    private var emptyShelf: some View {
        ShelfDropView { urls in coordinator.add(urls) }
            .overlay {
                Text("Перетащите файлы сюда или на челку")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tiles: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Config.HistoryGrid.tileSpacing) {
                ForEach(coordinator.shelf.items) { tile($0) }
            }
        }
    }

    private func tile(_ item: ShelfItem) -> some View {
        ShelfTileView(item: item, isSelected: selection.contains(item.id))
            .overlay {
                DragSourceRepresentable(
                    urlsForDrag: { coordinator.urls(for: dragIDs(for: item)) },
                    onClick: { commandHeld in click(item, commandHeld: commandHeld) })
            }
    }

    /// За выделенную плитку тянется всё выделение, за невыделенную — только она:
    /// схватив невыделенную, человек не ждёт, что уедет чужое выделение.
    private func dragIDs(for item: ShelfItem) -> [UUID] {
        selection.contains(item.id) ? selection.ids : [item.id]
    }

    private func click(_ item: ShelfItem, commandHeld: Bool) {
        selection = commandHeld ? selection.toggling(item.id)
                                : selection.replacing(with: item.id)
    }

    private func removeSelected() {
        coordinator.remove(selection.ids)
        selection = selection.cleared()
    }
}

/// Плитка файла на полке: иконка из системы и имя под ней. Выделенная обведена
/// рамкой цветом акцента — как в сетке истории.
///
/// Цвета только семантические: тема системная, своих палитр в проекте нет.
private struct ShelfTileView: View {
    let item: ShelfItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: Config.HistoryGrid.innerSpacing) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: Config.HistoryGrid.fileIconSide,
                       height: Config.HistoryGrid.fileIconSide)
            Text(item.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(Config.Shelf.nameLineLimit)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
        }
        .padding(Config.HistoryGrid.innerSpacing)
        .frame(width: Config.HistoryGrid.tileSide, height: Config.HistoryGrid.tileSide)
        .background(.quaternary)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isSelected ? Color.accentColor : .clear,
                               lineWidth: Config.HistoryGrid.selectionLineWidth)
        }
        // Имя на плитке обрезано: полное человек достаёт наведением.
        .help(item.url.path)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Config.HistoryGrid.tileCornerRadius)
    }
}
