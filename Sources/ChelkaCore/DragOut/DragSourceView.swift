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
    /// Файлы за это нажатие уже готовили. Без отдельного признака попытка
    /// повторялась бы на каждое движение мыши: копирование на диск и строчка
    /// в логе десятки раз за один жест.
    private var didPrepareForPress = false

    public func draggingSession(_ session: NSDraggingSession,
                                sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    public override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        didPrepareForPress = false
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !didPrepareForPress else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        guard (dx * dx + dy * dy).squareRoot() > Config.Drag.gestureThreshold else { return }
        didPrepareForPress = true

        let urls = urlsForDrag()
        // Тащить нечего: блоб исчез с диска, или у записи «файлы» пустой список.
        // Точку нажатия НЕ обнуляем — жест не начался, значит отпускание кнопки
        // обязано остаться кликом. Обнуление здесь съедало нажатие целиком:
        // плитка не отзывалась ни на жест, ни на клик.
        guard !urls.isEmpty else {
            NSLog("4elka: перетаскивать нечего, жест не начат — нажатие отдаю как клик")
            return
        }

        let items: [NSDraggingItem] = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let origin = convert(event.locationInWindow, from: nil)
            let side = Config.Drag.iconSide
            let shift = CGFloat(index) * Config.Drag.iconStackOffset
            item.setDraggingFrame(
                NSRect(x: origin.x - side / 2 + shift,
                       y: origin.y - side / 2 - shift,
                       width: side, height: side),
                contents: icon)
            return item
        }
        // Точка нажатия гаснет только когда сессия действительно началась: это
        // и есть признак «жест пошёл», по которому `mouseUp` не отдаёт клик.
        mouseDownPoint = nil
        beginDraggingSession(with: items, event: event, source: self)
    }

    /// Отпускание без начатого жеста — это клик. Признак «жест начался» —
    /// обнулённая точка нажатия: её сбрасывает `mouseDragged`, но только
    /// начав сессию перетаскивания.
    public override func mouseUp(with event: NSEvent) {
        let wasPressed = mouseDownPoint != nil
        mouseDownPoint = nil
        didPrepareForPress = false
        if wasPressed { onClick(event) }
    }
}
