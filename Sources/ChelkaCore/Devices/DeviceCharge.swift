import Foundation

public struct DeviceCharge: Equatable, Identifiable, Sendable {
    public enum Source: Equatable, Sendable { case mac, bluetooth, phone }

    public var id: String { name }
    public let name: String
    public let percent: Int
    public let isCharging: Bool
    public let source: Source
    public let symbol: String

    public init(name: String, percent: Int, isCharging: Bool, source: Source, symbol: String) {
        self.name = name
        self.percent = percent
        self.isCharging = isCharging
        self.source = source
        self.symbol = symbol
    }
}
