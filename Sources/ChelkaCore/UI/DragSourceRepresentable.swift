import AppKit
import SwiftUI

/// Прослойка, чтобы AppKit-жест перетаскивания (`DragSourceView` из Task 4)
/// работал поверх SwiftUI-сетки. Именно она делает `DragMaterializer` полезным:
/// SwiftUI тащит наружу только один элемент за раз, а нам нужны все выделенные.
///
/// Файлы готовятся лениво: `urlsForDrag` зовётся в момент начала жеста, а не
/// при создании вью — иначе временный каталог заполнялся бы копиями всего,
/// что человек когда-либо копировал.
///
/// Клик приходит оттуда же, а не из SwiftUI-жеста под плиткой: AppKit-вью
/// съедает `mouseDown`, и жест под ней просто не сработал бы.
public struct DragSourceRepresentable: NSViewRepresentable {
    public let urlsForDrag: () -> [URL]
    public let onClick: (_ commandHeld: Bool) -> Void

    public init(urlsForDrag: @escaping () -> [URL],
                onClick: @escaping (_ commandHeld: Bool) -> Void = { _ in }) {
        self.urlsForDrag = urlsForDrag
        self.onClick = onClick
    }

    public func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView(frame: .zero)
        apply(to: view)
        return view
    }

    public func updateNSView(_ view: DragSourceView, context: Context) {
        apply(to: view)
    }

    /// Замыкания пересоздаются на каждый рендер и захватывают свежее выделение,
    /// поэтому их надо переставлять и в `update`, а не только при создании.
    private func apply(to view: DragSourceView) {
        view.urlsForDrag = urlsForDrag
        let click = onClick
        view.onClick = { event in click(event.modifierFlags.contains(.command)) }
    }
}
