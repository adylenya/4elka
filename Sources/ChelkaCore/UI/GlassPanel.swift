import AppKit
import SwiftUI

/// Единственная обёртка над Liquid Glass. SwiftUI-модификатора `.glassEffect()`
/// в SDK этой системы нет — есть только стиль кнопок `.glass`, поэтому стекло
/// берётся из AppKit. Соседние стеклянные элементы заворачиваются в контейнер,
/// иначе каждый считается отдельным проходом отрисовки.
public struct GlassPanel<Content: View>: NSViewRepresentable {
    private let cornerRadius: CGFloat
    private let style: NSGlassEffectView.Style
    private let content: Content

    public init(cornerRadius: CGFloat = Config.Notch.cornerRadius,
                style: NSGlassEffectView.Style = .regular,
                @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.style = style
        self.content = content()
    }

    public func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.style = style
        let hosted = NSHostingView(rootView: content)
        hosted.translatesAutoresizingMaskIntoConstraints = false
        // `NSGlassEffectView.contentView` auto-pins the content's edges to its own
        // bounds (confirmed empirically), but `NSHostingView`'s default sizingOptions
        // (`.standardBounds`) keeps it at its SwiftUI-intrinsic size regardless —
        // the pin loses to that self-imposed size. Clearing it lets the content
        // actually stretch when the glass is resized (e.g. peek -> expanded).
        hosted.sizingOptions = []
        glass.contentView = hosted
        return glass
    }

    public func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        glass.cornerRadius = cornerRadius
        glass.style = style
        (glass.contentView as? NSHostingView<Content>)?.rootView = content
    }
}

/// Обёртка для группы соседних стеклянных элементов — сливает их и экономит проходы.
public struct GlassGroup<Content: View>: NSViewRepresentable {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = Config.Notch.glassGroupSpacing,
                @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public func makeNSView(context: Context) -> NSGlassEffectContainerView {
        let container = NSGlassEffectContainerView()
        container.spacing = spacing
        let hosted = NSHostingView(rootView: content)
        // Same fix as `GlassPanel`: without this, the content keeps its
        // SwiftUI-intrinsic size instead of following the container's resize.
        hosted.sizingOptions = []
        container.contentView = hosted
        return container
    }

    public func updateNSView(_ container: NSGlassEffectContainerView, context: Context) {
        container.spacing = spacing
    }
}
