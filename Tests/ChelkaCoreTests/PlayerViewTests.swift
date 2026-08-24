import Testing
import Foundation
@testable import ChelkaCore

/// Полоса позиции пересобирала вью два раза в секунду всегда: и на паузе, и при
/// закрытой панели, когда её вообще никто не видит. Приложение живёт в челке
/// целый день, поэтому это чистый расход батареи.
@Test func positionTicksOnlyWhilePlayingAndPanelIsOpen() {
    #expect(PlayerView.shouldTickPosition(isPlaying: true, panel: .expanded,
                                          showsPositionBar: true))
    #expect(!PlayerView.shouldTickPosition(isPlaying: false, panel: .expanded,
                                           showsPositionBar: true))
    #expect(!PlayerView.shouldTickPosition(isPlaying: true, panel: .hidden,
                                           showsPositionBar: true))
    #expect(!PlayerView.shouldTickPosition(isPlaying: true, panel: .peek,
                                           showsPositionBar: true))
    #expect(!PlayerView.shouldTickPosition(isPlaying: true, panel: .activity,
                                           showsPositionBar: true))
}

/// Полоса выключена настройкой — двигать нечего, и таймер заводить незачем.
@Test func positionDoesNotTickWhenTheBarIsTurnedOff() {
    #expect(!PlayerView.shouldTickPosition(isPlaying: true, panel: .expanded,
                                           showsPositionBar: false))
}

/// Тумблеры «Показывать обложку» и «Показывать полосу позиции» обязаны доходить
/// до плеера: иначе они только сохранялись бы в файл настроек.
@Test func playerOptionsComeFromSettings() {
    #expect(Settings.defaults.playerOptions == .defaults)
    var quiet = Settings.defaults
    quiet.showsArtwork = false
    quiet.showsPositionBar = false
    #expect(!quiet.playerOptions.showsArtwork)
    #expect(!quiet.playerOptions.showsPositionBar)
}
