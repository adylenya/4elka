import AppKit
import SwiftUI

/// Приёмник файлов: единственное место, где приложение узнаёт, что на него
/// что-то бросили.
///
/// Умеет работать обёрткой вокруг чужого содержимого (`embedding:`). Именно так
/// её и вешают на окна: приёмник становится корневым вью, а панель или зона
/// над челкой живут внутри него. Причина — как AppKit ищет получателя сброса:
/// он берёт вью под курсором и поднимается по **родителям** до первой, кто
/// зарегистрирован на этот тип. Сосед (например, фон под содержимым) в эту
/// цепочку не попадает, поэтому «принимать сброс в любом месте панели» умеет
/// только родитель, а не наложенный сверху слой. А сверху накладывать нельзя
/// вовсе: такой слой съел бы нажатия мыши у плиток истории и убил бы главный
/// жест приложения — перетаскивание наружу.
@MainActor
public final class FileDropView: NSView {
    public var onDrop: ([URL]) -> Void = { _ in }

    private var isTargeted = false {
        didSet { if isTargeted != oldValue { needsDisplay = true } }
    }

    /// Рамку рисуем только когда приёмник — самостоятельная зона в панели.
    /// Обёртке вокруг всего окна подсвечивать себя нечем: рамка по краю
    /// экрана выглядела бы поломкой, а не приглашением.
    private let showsHighlight: Bool

    public init(frame: NSRect = .zero, showsHighlight: Bool = false) {
        self.showsHighlight = showsHighlight
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    /// Растянуть содержимое по себе. Через констрейнты, а не через
    /// `autoresizingMask`: `NSHostingView` иначе держится своего размера,
    /// посчитанного по содержимому, и не следует за размером панели.
    public func embed(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = Self.operation(for: sender)
        isTargeted = operation.contains(.copy)
        return operation
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.operation(for: sender)
    }

    public override func draggingExited(_ sender: NSDraggingInfo?) { isTargeted = false }

    public override func draggingEnded(_ sender: NSDraggingInfo) { isTargeted = false }

    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !Self.fileURLs(in: sender).isEmpty
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        let urls = Self.fileURLs(in: sender)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsHighlight, isTargeted else { return }
        let inset = Config.Shelf.dropHighlightLineWidth / 2
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            xRadius: Config.Shelf.dropHighlightCornerRadius,
            yRadius: Config.Shelf.dropHighlightCornerRadius)
        path.lineWidth = Config.Shelf.dropHighlightLineWidth
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    /// Копия, а не перемещение: полка забирает **ссылку** на чужой файл,
    /// и исходник обязан остаться на месте.
    private static func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(in: sender).isEmpty ? [] : .copy
    }

    private static func fileURLs(in sender: NSDraggingInfo) -> [URL] {
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true])
        return (objects as? [URL]) ?? []
    }
}

/// Зона приёма файлов внутри SwiftUI — та самая пустая полка с приглашением
/// «кинь файлы сюда». Она же подсвечивается рамкой, когда над ней тащат файл.
public struct ShelfDropView: NSViewRepresentable {
    public let onDrop: ([URL]) -> Void

    public init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
    }

    public func makeNSView(context: Context) -> FileDropView {
        let view = FileDropView(showsHighlight: true)
        view.onDrop = onDrop
        return view
    }

    /// Замыкание пересоздаётся на каждый рендер и захватывает свежее
    /// состояние, поэтому его надо переставлять и в `update`.
    public func updateNSView(_ view: FileDropView, context: Context) {
        view.onDrop = onDrop
    }
}
