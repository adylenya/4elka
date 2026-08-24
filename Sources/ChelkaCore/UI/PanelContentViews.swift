import AppKit
import SwiftUI

/// «Фигура», продолжающая физическую челку в стороны и вниз, а не отдельная
/// плашка под ней. Стык с настоящей челкой должен быть незаметен, поэтому
/// фон здесь — единственный явно заданный (не семантический) цвет в проекте:
/// чёрный в любой теме, а не адаптивный `.primary`/`.secondary`. Форсируем
/// тёмную схему для содержимого сверху, чтобы `.foregroundStyle(.primary)` там
/// оставалось читаемым семантическим текстом, а не белым на белом в светлой теме.
/// Скруглены только нижние углы (`notchCornerRadius`) — верхние прижаты к
/// самому верху экрана, где скругление было бы не видно.
public struct NotchContinuationFigure<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .colorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: Config.Notch.notchCornerRadius,
                bottomTrailingRadius: Config.Notch.notchCornerRadius,
                topTrailingRadius: 0))
    }
}

/// Панель, у которой чёрная планка ровно по ширине самого выреза — а не во
/// всю ширину окна. Всё остальное сверху, слева и справа от выреза — обычное
/// стекло от самого верха экрана.
///
/// Раньше планка тянулась во всю ширину раскрытой панели (700+ точек), хотя
/// физический вырез — 220. Получались широкие чёрные «крылья» по бокам от
/// самой челки, которых вырез не занимает вовсе: не «челка продолжается», а
/// «поверх панели наклеена чёрная полоса». Владелец увидел это на живом
/// экране 24.08 и попросил прямо: чёрным должна быть только сама челка,
/// остальное — как панель. Это отдельное решение от `NotchContinuationFigure`
/// (карточка и наведение) — там чёрным целиком узкое окно, и это осталось
/// нетронутым: жалоба была именно про широкую раскрытую панель.
///
/// Стекло теперь квадратное сверху (панель прижата к самому верху экрана —
/// круглый угол там оставлял бы щель с рабочим столом) и скруглено только
/// снизу, поэтому отдельного трюка с прятаньем угла за планкой больше не
/// нужно: планка — самый верхний слой и просто рисуется поверх плоского верха
/// стекла в его собственной, куда меньшей области.
public struct NotchToppedPanel<Content: View>: View {
    private let geometry: NotchGeometry
    private let content: Content

    public init(geometry: NotchGeometry, @ViewBuilder content: () -> Content) {
        self.geometry = geometry
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            GlassPanel(cornerRadius: 0) { content.padding(.top, barHeight) }
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: Config.Notch.cornerRadius,
                    bottomTrailingRadius: Config.Notch.cornerRadius,
                    topTrailingRadius: 0))
            Color.black
                .frame(width: notchWidth, height: barHeight)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: Config.Notch.notchCornerRadius,
                    bottomTrailingRadius: Config.Notch.notchCornerRadius,
                    topTrailingRadius: 0))
        }
    }

    /// На экране без физического выреза планки нет вовсе: продолжать нечего, а
    /// запасная геометрия и так стоит ниже строки меню.
    private var barHeight: CGFloat {
        geometry.hasPhysicalNotch ? geometry.rect.height : 0
    }

    /// Ширина планки — ровно ширина самого выреза, не панели.
    private var notchWidth: CGFloat {
        geometry.hasPhysicalNotch ? geometry.rect.width : 0
    }
}

/// Тонкая подсказка, выезжающая из-под челки при наведении, и то же самое в
/// скрытом состоянии, где её никто не видит. Одно содержимое на два состояния
/// намеренно: проход мыши мимо челки не пересобирает дерево вью ни разу.
public struct PeekHintView: View {
    private let geometry: NotchGeometry

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    public var body: some View {
        NotchContinuationFigure {
            GeometryReader { proxy in
                let layout = NotchLayout.inPanel(size: proxy.size, geometry: geometry)
                Capsule()
                    .fill(.tertiary)
                    .frame(width: Config.Notch.peekHintSize.width,
                           height: Config.Notch.peekHintSize.height)
                    .position(x: layout.body.midX,
                              y: proxy.size.height - layout.body.midY)
            }
        }
    }
}

/// Содержимое фигуры-карточки: сама карточка сидит в теле, под челкой — там,
/// где `NotchLayout.inPanel` её не перекрывает. Крылья слева и справа от
/// челки зарезервированы (`PanelFrames` гарантирует им место), но пока пустые.
///
/// Картинка приходит уже прочитанной: чтение внутри отрисовки означало бы
/// перечитывание файла (до сорока мегабайт) на каждый тик таймера.
public struct ActivityFigureContent: View {
    private let event: ActivityEvent
    private let image: NSImage?
    private let geometry: NotchGeometry

    public init(event: ActivityEvent, image: NSImage?, geometry: NotchGeometry) {
        self.event = event
        self.image = image
        self.geometry = geometry
    }

    public var body: some View {
        NotchContinuationFigure {
            GeometryReader { proxy in
                let layout = NotchLayout.inPanel(size: proxy.size, geometry: geometry)
                ActivityCardView(event: event, image: image)
                    .frame(width: layout.body.width, height: layout.body.height)
                    .position(x: layout.body.midX,
                              y: proxy.size.height - layout.body.midY)
            }
        }
    }
}
