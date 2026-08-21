import Foundation

/// Единственное место, где живут константы. Магических чисел в коде быть не должно.
public enum Config {
    /// Общая таймзона приложения: её используют и погода, и преобразование времени.
    public static let timezone = "Asia/Almaty"

    public enum History {
        public static let textLimit = 200
        public static let imageLimit = 30
        public static let fileLimit = 50
        public static let maxImageBytes = 40 * 1024 * 1024
        public static let pollInterval: TimeInterval = 0.2
        public static let indexWriteDebounce: TimeInterval = 1.0
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
    }

    public enum Weather {
        public static let latitude = 51.1605
        public static let longitude = 71.4704
        public static let refreshInterval: TimeInterval = 15 * 60
        public static let plausibleCelsius = -70.0 ... 60.0
    }

    public enum Notch {
        /// Ширина плашки на экранах без челки.
        public static let fallbackWidth: CGFloat = 220
        public static let fallbackHeight: CGFloat = 32
        public static let expandedSize = CGSize(width: 640, height: 340)
    }
}
