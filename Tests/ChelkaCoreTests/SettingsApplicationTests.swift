import Testing
import Foundation
@testable import ChelkaCore

/// Настройка, которая никуда не доходит, хуже отсутствующей: отсутствующая
/// честна, а эта врёт — человек крутит ручку, значение честно ложится в файл,
/// и ничего не происходит.
///
/// Поэтому здесь проверяется не «значение сохранилось», а «поведение
/// изменилось»: тест на сохранение в проекте уже был и не поймал ничего.

@MainActor
private func center(_ settings: Settings) -> ActivityCenter {
    ActivityCenter(panelState: { .hidden }, settings: { settings })
}

/// Вид события, его тумблер в настройках и имя поля для сообщения об отказе.
private struct CardSource {
    let field: String
    let kind: ActivityEvent.Kind
    let turnOff: (inout Settings) -> Void
}

/// Все три вида карточек со своим тумблером. Таблицей, а не тремя тестами:
/// новый вид событий обязан появиться и здесь, иначе его тумблер снова
/// окажется нарисованным.
private func cardSources() -> [CardSource] {
    [CardSource(field: "cardsFromTrack", kind: .track) { $0.cardsFromTrack = false },
     CardSource(field: "cardsFromClipboard", kind: .clipboard) { $0.cardsFromClipboard = false },
     CardSource(field: "cardsFromBattery", kind: .battery) { $0.cardsFromBattery = false }]
}

// MARK: - Тумблеры источников карточек

@MainActor
@Test func disabledCardSourceNeverEvenEntersTheQueue() {
    // Выключенный источник обязан пропасть на входе, а не нарисоваться и
    // спрятаться: иначе он ещё и перебьёт показанную карточку, оказавшись
    // приоритетнее.
    for source in cardSources() {
        var off = Settings.defaults
        source.turnOff(&off)
        let quiet = center(off)
        quiet.submit(ActivityEvent(kind: source.kind, title: "событие"), now: Date())
        #expect(quiet.queue.current == nil, "\(source.field) выключен, а карточка выехала")
    }
}

@MainActor
@Test func cardSourceToggleSilencesItsOwnKindOnly() {
    // Тумблер, гасящий чужой вид, со стороны выглядит работающим — карточек
    // нет. Но человек, выключивший «о смене трека», теряет уведомления о
    // заряде и не понимает, почему.
    for source in cardSources() {
        var off = Settings.defaults
        source.turnOff(&off)
        let queue = center(off)
        for other in cardSources() where other.kind != source.kind {
            queue.clear()
            queue.submit(ActivityEvent(kind: other.kind, title: "событие"), now: Date())
            #expect(queue.queue.current != nil,
                    "выключен \(source.field), а пропало событие \(other.field)")
        }
    }
}

@MainActor
@Test func everyCardKindGetsThroughWhileItsToggleIsOn() {
    // Обратная половина требования: включённый тумблер обязан пропускать.
    // Без неё «ничего не выезжает вообще» тоже считалось бы успехом.
    for source in cardSources() {
        let queue = center(.defaults)
        queue.submit(ActivityEvent(kind: source.kind, title: "событие"), now: Date())
        #expect(queue.queue.current != nil, "\(source.field) включён, а карточки нет")
    }
}
