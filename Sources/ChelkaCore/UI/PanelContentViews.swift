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

/// Панель, у которой верхние точки высотой челки — та же чёрная фигура, а
/// стекло достаётся только содержимому ниже.
///
/// Раньше стекло заливало окно целиком, включая верхние 38 точек слева и справа
/// от выреза, и челка читалась как чёрный укус в стеклянной панели — дословно
/// первая жалоба владельца, вернувшаяся в раскрытом состоянии. Любое состояние,
/// прижатое к верху экрана, обязано рисовать эту полосу.
///
/// Стекло заезжает под полосу на величину своего скругления: иначе его
/// скруглённые верхние углы оставляли бы две прозрачные прорехи, через которые
/// виден рабочий стол. Полоса их накрывает, и стык читается как единая фигура.
///
/// Слева и справа от выреза внутри полосы зарезервировано место под короткое
/// (время, погода, заряд). Раскрытая панель им не пользуется намеренно: строка
/// высотой с челку читается плохо, а всё, что стоит показывать, уже лежит в
/// теле — плеер, погода и заряды. Крылья остаются под будущее короткое.
public struct NotchToppedPanel<Content: View>: View {
    private let geometry: NotchGeometry
    private let content: Content

    public init(geometry: NotchGeometry, @ViewBuilder content: () -> Content) {
        self.geometry = geometry
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Стекло само отступает на `glassInset`, чтобы его скруглённый
            // угол спрятался за планкой, — но планка выше этого отступа на
            // `glassContentInset`, и ровно на эту величину содержимое обязано
            // отступить ещё раз, иначе его верх рисуется в полосе, которую
            // планка всё ещё перекрывает. Замерено на живом экране 24.08:
            // без этой добавки обрезался верх плеера (обложка, заголовок).
            GlassPanel { content.padding(.top, contentInset) }
                .padding(.top, glassInset)
            Color.black
                .frame(height: barHeight)
        }
    }

    /// На экране без физического выреза полосы нет вовсе: продолжать нечего, а
    /// запасная геометрия и так стоит ниже строки меню.
    private var barHeight: CGFloat {
        geometry.hasPhysicalNotch ? geometry.rect.height : 0
    }

    private var glassInset: CGFloat { NotchLayout.glassInset(geometry: geometry) }
    private var contentInset: CGFloat { NotchLayout.glassContentInset(geometry: geometry) }
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
