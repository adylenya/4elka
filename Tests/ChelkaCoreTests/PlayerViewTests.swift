import Testing
import Foundation
@testable import ChelkaCore

/// Полоса позиции пересобирала вью два раза в секунду всегда: и на паузе, и при
/// закрытой панели, когда её вообще никто не видит. Приложение живёт в челке
/// целый день, поэтому это чистый расход батареи.
@Test func positionTicksOnlyWhilePlayingAndPanelIsOpen() {
    #expect(PlayerView.shouldTickPosition(isPlaying: true, panel: .expanded))
    #expect(!PlayerView.shouldTickPosition(isPlaying: false, panel: .expanded))
    #expect(!PlayerView.shouldTickPosition(isPlaying: true, panel: .hidden))
    #expect(!PlayerView.shouldTickPosition(isPlaying: true, panel: .peek))
    #expect(!PlayerView.shouldTickPosition(isPlaying: true, panel: .activity))
}
