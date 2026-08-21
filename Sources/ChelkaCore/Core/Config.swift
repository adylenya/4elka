import Carbon.HIToolbox
import Foundation

/// Единственное место, где живут константы. Магических чисел в коде быть не должно.
public enum Config {
    /// Общая таймзона приложения: её используют и погода, и преобразование времени.
    public static let timezone = "Asia/Almaty"

    /// Идентификатор бандла самого приложения — по нему `IgnoreRules` отличает
    /// собственные записи в буфере (например, клик по элементу истории) от чужих.
    public static let ownBundleID = "com.adylenya.4elka"

    public enum History {
        public static let textLimit = 200
        public static let imageLimit = 30
        public static let fileLimit = 50
        public static let maxImageBytes = 40 * 1024 * 1024
        public static let pollInterval: TimeInterval = 0.2
        public static let indexWriteDebounce: TimeInterval = 1.0
    }

    /// Перетаскивание наружу: имена подготовленных файлов и уборка за собой.
    public enum Drag {
        /// Сколько живёт подготовленный под жест файл, прежде чем его уберут.
        /// Час — с большим запасом на то, что получатель жеста читает файл
        /// уже после отпускания кнопки, и при этом каталог не растёт вечно.
        public static let tempLifetime: TimeInterval = 60 * 60
        /// Длина имени файла, вырезанного из текста. Сорок символов — строка,
        /// которая ещё читается в Finder целиком.
        public static let nameMaxLength = 40
        /// Штамп времени в имени снимка. Двоеточий в имени файла быть не может,
        /// поэтому часы-минуты-секунды разделены дефисом.
        public static let nameDateFormat = "yyyy-MM-dd HH-mm-ss"
    }

    /// Сетка истории в раскрытой панели.
    public enum HistoryGrid {
        public static let tileSide: CGFloat = 92
        public static let tileSpacing: CGFloat = 8
        public static let padding: CGFloat = 10
        public static let rowSpacing: CGFloat = 8
        /// Зазор внутри плитки: между иконкой и подписью, вокруг метки закрепления.
        public static let innerSpacing: CGFloat = 4
        /// Толщина рамки вокруг выделенной плитки.
        public static let selectionLineWidth: CGFloat = 2
        public static let tileCornerRadius: CGFloat = 8
        /// Сколько строк текста видно на плитке.
        public static let textLineLimit = 2
        /// Сторона иконки файла на плитке.
        public static let fileIconSide: CGFloat = 40
    }

    /// Полка файлов: полоса в раскрытой панели и подсветка зоны приёма.
    public enum Shelf {
        /// Высота полосы полки: плитка (`HistoryGrid.tileSide`) плюс заголовок
        /// с кнопками над ней и зазор между ними. Остальное тело панели
        /// достаётся сетке истории.
        public static let stripHeight: CGFloat = 128
        /// Зазор между заголовком полки и плитками.
        public static let innerSpacing: CGFloat = 6
        /// Толщина рамки, которой зона приёма подсвечивается под перетаскиванием.
        public static let dropHighlightLineWidth: CGFloat = 2
        /// Скругление этой рамки — под стать скруглению плиток.
        public static let dropHighlightCornerRadius: CGFloat = 10
        /// Сколько строк имени файла видно на плитке полки.
        public static let nameLineLimit = 2
    }

    public enum Battery {
        public static let lowThreshold = 20
        public static let highThreshold = 80
        public static let fullThreshold = 100
        public static let hysteresis = 5
        public static let pollInterval: TimeInterval = 60
    }

    public enum Activity {
        public static let duration: TimeInterval = 3
        /// Как часто тикает таймер, гасящий карточку по истечении `duration`.
        public static let tickInterval: TimeInterval = 0.25
        /// Насколько карточка шире самой челки — под текст и миниатюру.
        public static let cardExtraWidth: CGFloat = 260
        /// Минимальная ширина карточки на экранах без физической челки.
        public static let cardMinWidth: CGFloat = 320
        /// Высота содержимого карточки — полосы ПОД челкой, а не всей фигуры.
        /// Общая высота считается в `NotchLayout.cardHeight`: к этому числу
        /// прибавляется высота самой челки. Минимум диктует рисование:
        /// миниатюра 34 точки плюс отступы по 8.
        public static let cardBodyHeight: CGFloat = 50
    }

    public enum Weather {
        public static let latitude = 51.1605
        public static let longitude = 71.4704
        public static let refreshInterval: TimeInterval = 15 * 60
        /// С какого возраста данные считаются устаревшими и показываются с пометкой.
        public static let staleAfter: TimeInterval = 60 * 60
        public static let plausibleCelsius = -70.0 ... 60.0
    }

    public enum Notch {
        /// Ширина плашки на экранах без челки.
        public static let fallbackWidth: CGFloat = 220
        public static let fallbackHeight: CGFloat = 32
        public static let expandedSize = CGSize(width: 640, height: 340)
        /// Скругление стеклянных поверхностей.
        public static let cornerRadius: CGFloat = 16
        /// Расстояние, на котором соседнее стекло сливается в одно.
        public static let glassGroupSpacing: CGFloat = 8
        /// Минимальная ширина крыла фигуры, продолжающей челку по бокам —
        /// достаточно для иконки или короткой подписи (время, значок заряда).
        /// Гарантирует, что фигура расширяет челку в стороны даже если
        /// запрошенная ширина карточки меньше этого.
        public static let wingWidth: CGFloat = 64
        /// Скругление нижних углов фигуры, продолжающей челку. Меньше обычного
        /// `cornerRadius`: верхние углы не скругляются вовсе (прижаты к самому
        /// верху экрана), и стык должен читаться как продолжение самой челки,
        /// а не как отдельная скруглённая панель.
        public static let notchCornerRadius: CGFloat = 10
    }

    /// Глобальное сочетание клавиш, раскрывающее и складывающее панель.
    public enum Hotkey {
        /// ⌃⌥V. Буква та же, за которой человек и так тянется за буфером,
        /// но модификаторы свободные. ⌘⇧V, с которого начинали, брать нельзя:
        /// это системная «вставка без форматирования» почти во всех редакторах
        /// и браузерах, а глобальная регистрация забирает сочетание себе —
        /// то есть приложение ломало бы то, чем человек пользуется ежедневно.
        public static let defaultKeyCode = UInt32(kVK_ANSI_V)
        public static let defaultModifiers = UInt32(controlKey | optionKey)
        /// Подпись владельца регистрации в Carbon: четыре байта '4ELK'.
        /// Carbon требует именно четырёхбуквенный код, а не строку.
        public static let signature = OSType(0x34454C4B)
    }

    public enum Media {
        /// Как часто обновляется полоса позиции в интерфейсе.
        public static let positionTickInterval: TimeInterval = 0.5
        /// Сторона обложки в плеере.
        public static let artworkSide: CGFloat = 56
        /// Поток без единого перевода строки — либо баг адаптера, либо чужая
        /// поломка. Не даём буферу расти неограниченно в ожидании перевода строки.
        public static let maxPendingBytes = 1 * 1024 * 1024
        /// Первая пауза перед перезапуском упавшего процесса.
        public static let restartDelayInitial: TimeInterval = 1
        /// Потолок экспоненциального роста паузы между перезапусками.
        public static let restartDelayMax: TimeInterval = 30
        /// Процесс, проживший дольше этого срока, считается здоровым запуском —
        /// политика перезапуска сбрасывается в исходную.
        public static let healthyRunGrace: TimeInterval = 5
        /// Столько мгновенных смертей подряд означает, что адаптер отсутствует
        /// или сломан — дальше пытаться бессмысленно.
        public static let maxImmediateFailures = 5
    }
}
