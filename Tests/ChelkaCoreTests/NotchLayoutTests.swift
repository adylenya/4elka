import Testing
import AppKit
@testable import ChelkaCore

private let measured = NotchGeometry(
    rect: CGRect(x: 918, y: 1291, width: 220, height: 38), hasPhysicalNotch: true)

/// Размер окна, а не размер содержимого: `inPanel` проверяется на произвольной
/// рамке, а рамки состояний считает `PanelFrames`.
private let window = CGSize(width: 640, height: 378)

@Test func cardContinuesTheNotchInsteadOfHangingBelowIt() {
    // Фигура закреплена у верха экрана и продолжает челку, а не висит под ней.
    let frame = NotchLayout.cardFrame(size: CGSize(width: 320, height: 54), geometry: measured)
    #expect(frame.maxY == measured.rect.maxY)
    #expect(frame.midX == measured.rect.midX)
}

@Test func cardAlwaysHasWingsBesideTheNotch() {
    // Крылья должны быть даже если запрошенная ширина меньше челки: иначе
    // фигура её не расширяет и челка остаётся заметной.
    let narrow = NotchLayout.cardFrame(size: CGSize(width: 100, height: 54), geometry: measured)
    #expect(narrow.width >= measured.rect.width + Config.Notch.wingWidth * 2)
    let wing = (narrow.width - measured.rect.width) / 2
    #expect(wing >= Config.Notch.wingWidth)
}

@Test func cardIsAtLeastAsTallAsTheNotch() {
    // Фигура ниже челки бессмысленна: ей нечего продолжать. Проверяем не
    // «строго больше» — тело в одну точку такую проверку устраивало, — а что
    // выступ ровно тот, который назван константой.
    let squat = NotchLayout.cardFrame(size: CGSize(width: 320, height: 5), geometry: measured)
    #expect(squat.height == measured.rect.height + Config.Notch.minFigureOvershoot)
    #expect(Config.Notch.minFigureOvershoot > 0)
}

@Test func panelBodyStartsBelowTheNotch() {
    let layout = NotchLayout.inPanel(size: window, geometry: measured)
    // Тело занимает всё, кроме верхней полосы высотой челки.
    #expect(layout.body.height == window.height - measured.rect.height)
    #expect(layout.body.minY == 0)
    #expect(layout.body.width == window.width)
}

@Test func stripsSitBesideTheNotchAndNeverUnderIt() {
    let layout = NotchLayout.inPanel(size: window, geometry: measured)
    // Полосы в верхних 38 точках, слева и справа от челки, и не пересекают её.
    #expect(layout.leftStrip.height == measured.rect.height)
    #expect(layout.rightStrip.height == measured.rect.height)
    #expect(layout.leftStrip.maxY == window.height)
    let notchInPanel = (window.width - measured.rect.width) / 2
    #expect(abs(layout.leftStrip.width - notchInPanel) < 0.001)
    #expect(abs(layout.rightStrip.width - notchInPanel) < 0.001)
    #expect(layout.leftStrip.maxX <= layout.rightStrip.minX)
}

@Test func stripsAreEmptyWhenPanelIsNarrowerThanTheNotch() {
    let narrow = CGSize(width: 120, height: 200)
    let layout = NotchLayout.inPanel(size: narrow, geometry: measured)
    #expect(layout.leftStrip.width == 0)
    #expect(layout.rightStrip.width == 0)
    // Тело при этом всё равно есть.
    #expect(layout.body.height > 0)
}

@Test func withoutPhysicalNotchThereIsNoStripAndBodyIsWhole() {
    let plain = NotchGeometry(rect: CGRect(x: 850, y: 1048, width: 220, height: 32),
                              hasPhysicalNotch: false)
    let layout = NotchLayout.inPanel(size: window, geometry: plain)
    #expect(layout.leftStrip.isEmpty)
    #expect(layout.rightStrip.isEmpty)
    #expect(layout.body.height == window.height)
}

@Test func panelTakesKeyboardOnlyWhenExpanded() {
    // Карточка перехватывала набор текста, потому что окну разрешалось
    // становиться клавиатурным всегда.
    for state in [PanelState.hidden, .peek, .activity] {
        #expect(!NotchPanel.allowsKeyboard(in: state))
    }
    #expect(NotchPanel.allowsKeyboard(in: .expanded))
}

@Test func cardHeightAddsTheNotchOnTopOfTheContent() {
    // Замерено на живом экране: фигура высотой 54 точки при челке 38 оставляла
    // содержимому 16 точек, и вторая строка карточки («скопировано») обрезалась
    // нижним краем фигуры. Высоту челки надо прибавлять к высоте содержимого,
    // а не рассчитывать, что содержимое поместится в общую высоту.
    let content: CGFloat = 50
    let height = NotchLayout.cardHeight(contentHeight: content, geometry: measured)
    #expect(height == content + measured.rect.height)

    let frame = NotchLayout.cardFrame(size: CGSize(width: 320, height: height),
                                      geometry: measured)
    let layout = NotchLayout.inPanel(size: frame.size, geometry: measured)
    #expect(layout.body.height == content)
}

@Test func cardHeightOnScreenWithoutNotchIsTheContentAlone() {
    let plain = NotchGeometry(rect: CGRect(x: 850, y: 1048, width: 220, height: 32),
                              hasPhysicalNotch: false)
    #expect(NotchLayout.cardHeight(contentHeight: 50, geometry: plain) == 50)
}

@Test func activityContentIsTallEnoughForIconAndTwoLinesWithRoomToSpare() {
    // Раньше этот тест перепечатывал литералы из вью (34 и 8) и её не защищал:
    // поднимешь миниатюру — тест зелёный, а содержимое снова обрезано. Теперь
    // минимум выведен из тех же констант, которыми рисует вью, и над ним
    // требуется запас.
    #expect(Config.Activity.cardBodyHeight > Config.Activity.cardContentMinHeight)
    #expect(Config.Activity.cardContentMinHeight
            == Config.Activity.cardThumbnailSide + Config.Activity.cardVerticalPadding * 2)
}
