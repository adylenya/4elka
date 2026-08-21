import AppKit

/// Начинает сессию перетаскивания сразу на несколько файлов.
public final class DragSourceView: NSView, NSDraggingSource {
    public var urlsForDrag: () -> [URL] = { [] }

    /// Клик, который эта вью иначе съела бы молча.
    ///
    /// Вью перекрывает содержимое под собой и не передаёт `mouseDown` дальше,
    /// поэтому SwiftUI-жест под ней не срабатывает вовсе — без этого обратного
    /// вызова плитка истории перестала бы отзываться на клик. Отличить клик от
    /// жеста просто: начавшееся перетаскивание уводит события в свой вложенный
    /// цикл, и `mouseUp` сюда уже не приходит.
    public var onClick: (NSEvent) -> Void = { _ in }

    private var mouseDownPoint: NSPoint?

    public func draggingSession(_ session: NSDraggingSession,
                                sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    public override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        guard (dx * dx + dy * dy).squareRoot() > 4 else { return }
        mouseDownPoint = nil

        let urls = urlsForDrag()
        guard !urls.isEmpty else { return }

        let items: [NSDraggingItem] = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let origin = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(
                NSRect(x: origin.x - 32 + CGFloat(index) * 8,
                       y: origin.y - 32 - CGFloat(index) * 8,
                       width: 64, height: 64),
                contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    /// Отпускание без начатого жеста — это клик. Признак «жест начался» —
    /// обнулённая точка нажатия: её сбрасывает `mouseDragged`, перешагнув порог.
    public override func mouseUp(with event: NSEvent) {
        let wasPressed = mouseDownPoint != nil
        mouseDownPoint = nil
        if wasPressed { onClick(event) }
    }
}
