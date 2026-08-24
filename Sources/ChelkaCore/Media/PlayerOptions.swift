import Foundation

/// Что показывать в плеере. Человек крутит эти два тумблера в настройках
/// («Показывать обложку», «Показывать полосу позиции»), и без параметра они
/// только сохранялись бы в файл, ничего не меняя.
///
/// Тип из одних значений: `Sendable` достаётся бесплатно, окон он не трогает.
public struct PlayerOptions: Equatable, Sendable {
    public let showsArtwork: Bool
    public let showsPositionBar: Bool

    public init(showsArtwork: Bool, showsPositionBar: Bool) {
        self.showsArtwork = showsArtwork
        self.showsPositionBar = showsPositionBar
    }

    public static let defaults = PlayerOptions(showsArtwork: Config.Player.showsArtwork,
                                               showsPositionBar: Config.Player.showsPositionBar)
}
