import SwiftUI

/// Содержимое раскрытой панели целиком — то место, где подсистемы наконец
/// сходятся вместе.
///
/// Сверху вниз: плеер, сетка истории с поиском и вкладками, полка файлов и
/// нижняя полоса — календарь-месяц слева, погода и заряды устройств справа.
/// Порядок задан `PanelSections.order`, а высоты — `Config.Panel`: раскрытая
/// панель обязана вмещать все разделы, а не обрезать их нижним краем.
///
/// **Разделы не пропадают, когда наполнять их нечем** — вместо содержимого
/// показывается строка из `PanelPlaceholder`. Погода обновляется раз в четверть
/// часа, заряды раз в минуту, плеер — при каждой смене трека; исчезающий раздел
/// дёргал бы раскладку при каждом таком обновлении.
///
/// Место под челкой ей уже отдано `NotchToppedPanel`, поэтому полосу сверху она
/// не считает и занимает всё стекло целиком. Крылья слева и справа от челки не
/// используются: строка высотой с челку читается плохо, а рисовать там плитки
/// или календарь нельзя.
///
/// Вьюха тонкая и тестами не покрывается: состав разделов проверяется в
/// `PanelSections`, размеры — в `PanelSectionsTests`, содержимое каждого
/// раздела — в тестах своей подсистемы.
public struct ExpandedPanelContent: View {
    private let coordinator: ClipboardCoordinator
    private let blobs: BlobStore
    private let shelf: ShelfCoordinator
    private let services: ServiceContainer
    /// Состояние панели нужно ровно за одним: решить, тикать ли полосе позиции
    /// в плеере. Приходит значением, а не читается из автомата: содержимое
    /// пересобирается только при смене состояния, и на момент сборки оно уже
    /// известно.
    private let panel: PanelState
    /// Календарь с первым днём недели из настроек.
    private let calendar: Calendar
    private let onClose: () -> Void

    public init(coordinator: ClipboardCoordinator, blobs: BlobStore,
                shelf: ShelfCoordinator, services: ServiceContainer,
                panel: PanelState, calendar: Calendar,
                onClose: @escaping () -> Void) {
        self.coordinator = coordinator
        self.blobs = blobs
        self.shelf = shelf
        self.services = services
        self.panel = panel
        self.calendar = calendar
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: Config.Panel.sectionSpacing) {
            player
            HistoryGridView(coordinator: coordinator, blobs: blobs, onClose: onClose)
            ShelfView(coordinator: shelf)
                .padding(.horizontal, Config.HistoryGrid.padding)
            bottomBar
        }
        // Отступ сверху и снизу — здесь, один раз на всё содержимое, и он же
        // учтён в `Config.Panel.contentHeight`. Отступ, добавленный к разделу
        // мимо этого расчёта, отбирал бы место у сетки истории.
        .padding(.vertical, Config.Panel.verticalPadding)
    }

    private var player: some View {
        PlayerView(coordinator: services.media, panel: panel,
                   options: { services.playerOptions })
            .frame(height: Config.Panel.playerHeight)
            .padding(.horizontal, Config.HistoryGrid.padding)
    }

    /// Нижняя полоса: календарь занимает левую часть, погода и заряды — правую.
    /// Высота фиксирована по самой высокой сетке месяца: месяц из шести строк
    /// не должен раздвигать полосу и сдвигать всё, что выше.
    private var bottomBar: some View {
        HStack(alignment: .top, spacing: Config.Panel.sectionSpacing) {
            MonthView(calendar: calendar, locale: .current)
                .frame(width: Config.Panel.calendarWidth)
            Divider()
            VStack(alignment: .leading, spacing: Config.Panel.rowSpacing) {
                WeatherView(provider: services.weather, city: { services.weatherCity })
                Divider()
                DevicesView(provider: services.devices,
                            showsPhone: { services.showsPhone })
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Config.Panel.bottomBarHeight)
        .padding(.horizontal, Config.HistoryGrid.padding)
    }
}
