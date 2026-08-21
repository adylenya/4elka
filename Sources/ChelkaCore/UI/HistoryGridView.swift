import AppKit
import SwiftUI

/// Панель истории: поле поиска, вкладки, сетка плиток.
///
/// Ввод. Обычный клик кладёт элемент в системный буфер и закрывает панель —
/// вставляет человек сам своим `cmd+V`, синтетических нажатий мы не посылаем
/// и разрешения на управление компьютером не просим. `cmd`-клик переключает
/// выделение, `⌫` удаляет выделенное, `⌘P` закрепляет, `Esc` закрывает.
///
/// Почему клик приходит из AppKit, а не из SwiftUI-жеста: поверх каждой плитки
/// лежит `DragSourceRepresentable`, и AppKit-вью съедает `mouseDown` — жест под
/// ней просто не сработал бы. `ClickableDragSourceView` возвращает клик обратно.
///
/// Фокус живёт в двух местах. Панель открывается с фокусом в поиске, чтобы
/// можно было сразу печатать; `⌫` и `⌘P` относятся к сетке, поэтому выделение
/// плитки уводит фокус туда — иначе `⌫` стирал бы букву в поиске вместо того,
/// чтобы удалить выделенное.
///
/// Вьюха тонкая и тестами не покрывается: отбор проверяется в `HistorySearch`,
/// выделение — в `Selection`, групповые операции — в `ClipboardCoordinator`.
public struct HistoryGridView: View {
    private enum Field: Hashable { case search, grid }

    @ObservedObject private var coordinator: ClipboardCoordinator
    private let blobs: BlobStore
    private let onClose: () -> Void

    @State private var tab: HistoryTab = .all
    @State private var query: String = ""
    @State private var selection = Selection()
    @FocusState private var focus: Field?

    public init(coordinator: ClipboardCoordinator, blobs: BlobStore,
                onClose: @escaping () -> Void) {
        self.coordinator = coordinator
        self.blobs = blobs
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: Config.HistoryGrid.rowSpacing) {
            searchField
            tabPicker
            content(for: visibleItems)
        }
        .padding(Config.HistoryGrid.padding)
        .onAppear { focus = .search }
        // Выделение не должно переживать смену вкладки и строки поиска: `⌫` и
        // `⌘P` иначе работают по невидимому, а отмены у нас нет.
        .onChange(of: tab) { narrowSelectionToVisible() }
        .onChange(of: query) { narrowSelectionToVisible() }
        .onExitCommand(perform: onClose)
    }

    private var searchField: some View {
        HStack(spacing: Config.HistoryGrid.tileSpacing) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Поиск", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .focused($focus, equals: .search)
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(HistoryTab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// Пустая сетка выглядит как поломка, поэтому вместо неё строка: разная
    /// для «история пуста» и «поиск ничего не нашёл» — это разные положения.
    @ViewBuilder
    private func content(for items: [ClipItem]) -> some View {
        if items.isEmpty {
            Spacer()
            Text(coordinator.history.items.isEmpty ? "история пуста" : "ничего не нашлось")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            grid(items)
        }
    }

    private func grid(_ items: [ClipItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Config.HistoryGrid.tileSpacing) {
                ForEach(items) { tile($0) }
            }
        }
        .focusable()
        .focused($focus, equals: .grid)
        .onKeyPress(.delete) { removeSelected() }
        .onKeyPress(keys: ["p"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            return pinSelected()
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Config.HistoryGrid.tileSide),
                  spacing: Config.HistoryGrid.tileSpacing)]
    }

    private func tile(_ item: ClipItem) -> some View {
        ItemTileView(item: item, blobs: blobs, isSelected: selection.contains(item.id))
            .overlay {
                DragSourceRepresentable(
                    urlsForDrag: { coordinator.materializeForDrag(dragIDs(for: item)) },
                    onClick: { commandHeld in click(item, commandHeld: commandHeld) })
            }
    }

    private var visibleItems: [ClipItem] {
        HistorySearch.filter(coordinator.history.items, tab: tab, query: query)
    }

    /// За выделенную плитку тянется всё выделение, за невыделенную — только она:
    /// схватив невыделенную, человек не ждёт, что уедет чужое выделение.
    private func dragIDs(for item: ClipItem) -> [UUID] {
        selection.contains(item.id) ? selection.ids : [item.id]
    }

    private func click(_ item: ClipItem, commandHeld: Bool) {
        guard commandHeld else {
            coordinator.copyToPasteboard(item.id)
            onClose()
            return
        }
        selection = selection.toggling(item.id)
        focus = .grid
    }

    /// Сужение зовётся и на смену вкладки с поиском, и перед самой операцией:
    /// первое убирает рамку с того, что человек больше не видит, второе не даёт
    /// невидимому попасть под операцию, даже если состояние успело разойтись.
    private func narrowSelectionToVisible() {
        let narrowed = selection.narrowed(to: visibleItems.map(\.id))
        guard narrowed != selection else { return }
        selection = narrowed
    }

    private func removeSelected() -> KeyPress.Result {
        narrowSelectionToVisible()
        guard !selection.isEmpty else { return .ignored }
        coordinator.remove(selection.ids)
        selection = selection.cleared()
        return .handled
    }

    private func pinSelected() -> KeyPress.Result {
        narrowSelectionToVisible()
        guard !selection.isEmpty else { return .ignored }
        coordinator.togglePin(selection.ids)
        return .handled
    }
}
