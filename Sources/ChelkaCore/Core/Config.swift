import Carbon.HIToolbox
import Foundation

/// Единственное место, где живут константы. Магических чисел в коде быть не должно.
public enum Config {
    /// Общая таймзона приложения: её используют и погода, и преобразование времени.
    public static let timezone = "Asia/Almaty"

    /// Секунд в минуте. Настройки погоды человек крутит в минутах, а таймеры
    /// живут в секундах — перевод должен называться, а не стоять числом.
    public static let secondsInMinute: TimeInterval = 60

    /// Байт в мегабайте. Настройки крутят потолок размера в мегабайтах —
    /// человек понимает «40», а не «41943040».
    public static let bytesInMegabyte = 1024 * 1024

    /// Идентификатор бандла самого приложения — по нему `IgnoreRules` отличает
    /// собственные записи в буфере (например, клик по элементу истории) от чужих.
    public static let ownBundleID = "com.adylenya.4elka"

    public enum History {
        public static let textLimit = 200
        public static let imageLimit = 30
        public static let fileLimit = 50
        public static let maxImageBytes = 40 * Config.bytesInMegabyte
        public static let pollInterval: TimeInterval = 0.2
        public static let indexWriteDebounce: TimeInterval = 1.0
        /// Текст лежит в `index.json` прямо в тексте, и файл перезаписывается на
        /// каждое изменение истории — поэтому предел для текста куда строже, чем
        /// для картинки. Два мегабайта это около миллиона символов: всё, что
        /// человек копирует руками, влезает с запасом, а дамп на сорок мегабайт
        /// в историю уже не попадёт и не будет таскаться по диску.
        public static let maxTextBytes = 2 * 1024 * 1024
        /// Насколько свежий файл картинки уборка обходит стороной. Файл пишется
        /// на диск раньше, чем индекс со ссылкой на него, и в этом зазоре он ещё
        /// никем не удерживается — минута с запасом покрывает отложенную запись.
        public static let orphanBlobGrace: TimeInterval = 60
    }

    /// Файлы состояния на диске: история, полка, настройки. Общее для всех,
    /// а не по копии на хранилище — испорченный файл откладывается в сторону
    /// одинаково везде.
    public enum StateFile {
        /// Метка времени в имени отложенного испорченного файла. Двоеточий
        /// в имени файла быть не может, поэтому время слитно.
        public static let brokenDateFormat = "yyyy-MM-dd-HHmmss"
        /// Пометка в имени файла, отложенного из-за непрочитанного содержимого.
        public static let brokenSuffix = "broken"
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
        /// Насколько надо увести мышь, чтобы это считалось перетаскиванием, а не
        /// кликом с дрожью руки. Четыре точки — меньше, чем дрожит палец на
        /// трекпаде при нажатии, и заметно меньше самой плитки.
        public static let gestureThreshold: CGFloat = 4
        /// Сторона иконки, летящей за курсором во время жеста. Курсор держится
        /// в её центре, поэтому смещение кадра — половина этой стороны.
        public static let iconSide: CGFloat = 64
        /// Сдвиг каждой следующей иконки в стопке: так видно, что тащат
        /// несколько файлов, а не один.
        public static let iconStackOffset: CGFloat = 8
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
        /// Сторона миниатюры и значка в карточке.
        public static let cardThumbnailSide: CGFloat = 34
        public static let cardThumbnailCornerRadius: CGFloat = 6
        /// Зазор между миниатюрой и текстом.
        public static let cardSpacing: CGFloat = 10
        /// Зазор между заголовком карточки и подписью под ним.
        public static let cardTextSpacing: CGFloat = 1
        public static let cardHorizontalPadding: CGFloat = 12
        public static let cardVerticalPadding: CGFloat = 8
        public static let cardTitleFontSize: CGFloat = 12
        public static let cardSubtitleFontSize: CGFloat = 10
        public static let cardIconFontSize: CGFloat = 16
        /// Минимум, ниже которого содержимое карточки обрезается: миниатюра
        /// плюс вертикальные отступы. Выведен из тех же констант, которыми
        /// рисует вью, а не перепечатан числом: поднимешь миниатюру — минимум
        /// поднимется сам, и тест это увидит.
        public static let cardContentMinHeight =
            cardThumbnailSide + cardVerticalPadding * 2
        /// Запас над минимумом. Раньше высота содержимого стояла ровно на
        /// вычисленном минимуме, и любая правка рисования обрезала карточку.
        public static let cardBodySlack: CGFloat = 6
        /// Высота содержимого карточки — полосы ПОД челкой, а не всей фигуры.
        /// Общая высота считается в `NotchLayout.cardHeight`: к этому числу
        /// прибавляется высота самой челки.
        public static let cardBodyHeight = cardContentMinHeight + cardBodySlack
    }

    public enum Weather {
        public static let latitude = 51.1605
        public static let longitude = 71.4704
        /// Подпись к координатам по умолчанию. В настройках город выбирается
        /// по названию, а не вводом чисел, поэтому имя нужно и в Config.
        public static let cityName = "Астана"
        public static let refreshInterval: TimeInterval = 15 * 60
        /// С какого возраста данные считаются устаревшими и показываются с пометкой.
        public static let staleAfter: TimeInterval = 60 * 60
        public static let plausibleCelsius = -70.0 ... 60.0
    }

    /// Календарь: первый день недели, когда человек задаёт его вручную, а не
    /// берёт из системы. Двойка — понедельник (нумерация `Calendar.firstWeekday`,
    /// где 1 — воскресенье).
    public enum Calendar {
        public static let manualFirstWeekday = 2
    }

    /// Плеер в раскрытой панели: что показывать по умолчанию.
    public enum Player {
        public static let showsArtwork = true
        public static let showsPositionBar = true
    }

    /// Поведение панели по умолчанию: раскрываться по наведению, а не только
    /// по клику. Наведение — основной жест, клик остаётся как страховка.
    public enum Behavior {
        public static let opensOnHover = true
    }

    /// Комбинация, раскрывающая панель. Значения — карбоновые: именно их
    /// принимает `RegisterEventHotKey`, и разрешения на управление
    /// компьютером он, в отличие от глобального монитора событий, не просит.
    public enum Hotkey {
        /// ⌃⌥V. Буква та же, за которой человек и так тянется за буфером,
        /// но модификаторы свободные. ⌘⇧V, с которого начинали, брать нельзя:
        /// это системная «вставка без форматирования» почти во всех редакторах
        /// и браузерах, а глобальная регистрация забирает сочетание себе —
        /// то есть приложение ломало бы то, чем человек пользуется ежедневно.
        public static let defaultKeyCode = UInt32(kVK_ANSI_V)
        public static let defaultModifiers = UInt32(controlKey | optionKey)
        /// То же самое числами со знаком — в таком виде это лежит в настройках
        /// и уходит в Carbon. Держим рядом, чтобы сочетание по умолчанию
        /// оставалось в одном месте: два независимых определения уже разошлись
        /// один раз при слиянии.
        public static let keyCode = Int(defaultKeyCode)
        public static let modifiers = Int(defaultModifiers)
        /// Хоть один из этих флагов обязателен: комбинация без ⌘/⌃/⌥ отобрала
        /// бы у человека обычную букву во всех приложениях сразу.
        public static let requiredModifiers = Int(cmdKey | controlKey | optionKey)
        /// Диапазон кодов клавиш виртуальной клавиатуры macOS.
        public static let keyCodeRange = 0...127
        /// Подпись владельца регистрации в Carbon: четыре байта '4ELK'.
        /// Carbon требует именно четырёхбуквенный код, а не строку.
        public static let signature = OSType(0x34454C4B)
    }

    /// Окно настроек: размеры, которые нельзя выводить из содержимого.
    public enum SettingsWindow {
        public static let size = CGSize(width: 560, height: 660)
        /// Минимум, ниже которого подписи слева начинают наезжать на поля.
        public static let minSize = CGSize(width: 460, height: 420)
        public static let numberFieldWidth: CGFloat = 64
        /// Зазор между подписью строки и пояснением под ней.
        public static let hintSpacing: CGFloat = 2
        public static let coordinateFieldWidth: CGFloat = 88
        public static let rowSpacing: CGFloat = 6
        /// Высота списка приложений и списка городов: примерно пять строк —
        /// видно, что это список, и он не съедает окно целиком.
        public static let listHeight: CGFloat = 120
        /// Зазор между строками внутри такого списка.
        public static let listRowSpacing: CGFloat = 4
        /// Шаг стрелок у квот истории: по одному щёлкать двести раз незачем.
        public static let quotaStep = 10
        /// Шаг стрелок у времени жизни карточки, в секундах.
        public static let durationStep: TimeInterval = 0.5
        /// Шаг стрелок у координат — примерно десять километров.
        public static let coordinateStep = 0.1
    }

    /// Границы, в которые загоняются настройки, отредактированные человеком.
    /// Человек может ввести что угодно, а файл настроек — поправить руками.
    public enum Limits {
        public static let historyQuota = 1...5000
        public static let imageMegabytes = 1...500
        /// Карточка живёт от полусекунды (меньше — не успеть прочитать) до
        /// тридцати секунд (дольше — это уже не выезжающая карточка, а плашка,
        /// висящая под челкой постоянно).
        public static let activityDuration: ClosedRange<TimeInterval> = 0.5...30
        /// Нижний порог не может быть сотней: выше него обязан лежать верхний.
        public static let batteryLow = 1...99
        public static let batteryHigh = 1...100
        public static let hysteresis = 1...20
        public static let latitude = -90.0...90.0
        public static let longitude = -180.0...180.0
        public static let weatherRefreshMinutes = 1...240
        public static let weatherStaleMinutes = 1...1440
        /// Нумерация `Calendar.firstWeekday`: 1 — воскресенье, 7 — суббота.
        public static let firstWeekday = 1...7
    }

    public enum Notch {
        /// Ширина плашки на экранах без челки.
        public static let fallbackWidth: CGFloat = 220
        public static let fallbackHeight: CGFloat = 32
        /// Размер СОДЕРЖИМОГО раскрытой панели — того, что лежит ниже челки.
        /// Полную высоту окна считает `PanelFrames`: к этому числу прибавляется
        /// высота челки. Раньше это была полная высота, вырез съедал из неё
        /// 38 точек, и сетку истории обрезало нижним краем.
        public static let expandedSize = CGSize(width: 640, height: 340)
        /// Высота подсказки, выезжающей из-под челки при наведении. Раньше
        /// наведение просило размером ровно вырез — тело выходило нулевой
        /// высоты, и состояние наведения не показывало ничего.
        public static let peekBodyHeight: CGFloat = 12
        /// Ширина и высота самой подсказки внутри этой полосы — короткая
        /// чёрточка, продолжающая челку вниз.
        public static let peekHintSize = CGSize(width: 36, height: 4)
        /// Насколько фигура обязана быть ниже челки, чтобы её было видно.
        /// Раньше здесь стояла голая единица в расчёте высоты.
        public static let minFigureOvershoot: CGFloat = 1
        /// Насколько уровень окна зоны-триггера выше уровня панели. Зона обязана
        /// лежать строго выше: панель поднимается на передний план на каждом
        /// переходе и иначе накрывает зону собой, съедая наведение и клик —
        /// то есть главный жест приложения не работает вовсе.
        public static let triggerLevelOffset = 1
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

    public enum Media {
        /// Как часто обновляется полоса позиции в интерфейсе.
        public static let positionTickInterval: TimeInterval = 0.5
        /// Сторона обложки в плеере.
        public static let artworkSide: CGFloat = 56
        /// Поток без единого перевода строки — либо баг адаптера, либо чужая
        /// поломка. Не даём НЕДОСОБРАННОМУ остатку расти неограниченно в
        /// ожидании перевода строки. Целые строки порогом не режутся вовсе:
        /// обложка приходит в потоке как base64 (это +33% к байтам картинки),
        /// и картинка на 800 КБ даёт строку под 1,1 МБ — при пороге в мегабайт
        /// каждое обновление такого плеера обрубалось. Восемь мегабайт — запас
        /// на многомегабайтную обложку и всё ещё не «вся память».
        public static let maxPendingBytes = 8 * 1024 * 1024
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
        /// Сколько последних строк потока ошибок адаптера держать для лога.
        /// Больше не нужно: причина отказа perl — в первых же строках, а
        /// хранить весь поток целиком значило бы держать его в памяти вечно.
        public static let errorTailLines = 20
    }
}
