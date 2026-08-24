import AppKit

/// Какой экран считать своим. Отдельная чистая функция, потому что раннее
/// «нет главного экрана — выходим» бросало весь запуск: приложение оставалось
/// без панели, без зоны, без иконки в строке меню и без наблюдателя буфера,
/// а выключить его можно было только через мониторинг системы.
public enum ScreenChoice {
    /// Главный экран, иначе первый доступный, иначе никакого. Обобщённая по
    /// типу, чтобы проверялась тестом без физического дисплея.
    public static func chosen<Screen>(main: Screen?, all: [Screen]) -> Screen? {
        main ?? all.first
    }

    /// Геометрия челки выбранного экрана. Экранов нет вовсе — `NotchGeometry.none`:
    /// окна никуда не ставятся, но приложение остаётся живым и пересчитается
    /// по следующему уведомлению о смене экранов.
    @MainActor
    public static func geometry(main: NSScreen? = NSScreen.main,
                               all: [NSScreen] = NSScreen.screens) -> NotchGeometry {
        guard let screen = chosen(main: main, all: all) else { return .none }
        return NotchGeometry.current(screen: screen)
    }
}

/// Наблюдатель за сменой экранов и разрешения. Спека требует прямым текстом:
/// геометрия пересчитывается на смену экрана и разрешения, приложение не должно
/// молча перестать работать при подключении монитора.
///
/// Сценарии, которые он закрывает: сменил масштаб в мониторах — панель и
/// невидимая зона остаются на старых координатах; вход с закрытой крышкой на
/// док-станции, где геометрия сначала запасная; два экрана, где панель осталась
/// на том, который был главным в момент запуска.
@MainActor
public final class ScreenWatcher {
    private var token: NSObjectProtocol?

    /// Уведомление приходит на главном потоке, поэтому наблюдатель ставится без
    /// очереди: блок исполняется синхронно там же, где его послали, и
    /// пересчёт геометрии не отстаёт на проход цикла событий.
    public init(onChange: @escaping @MainActor () -> Void) {
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: nil) { _ in
                MainActor.assumeIsolated { onChange() }
            }
    }

    public func stop() {
        guard let token else { return }
        NotificationCenter.default.removeObserver(token)
        self.token = nil
    }
}
