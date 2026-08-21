import Testing
import Foundation
@testable import ChelkaCore

private let now = Date(timeIntervalSince1970: 100_000)

private func file(_ name: String, age: TimeInterval) -> BlobGarbage.File {
    BlobGarbage.File(name: name, modifiedAt: now.addingTimeInterval(-age))
}

/// Файл, на который не ссылается ни один элемент истории, убрать больше нечем:
/// история сама отбрасывает элементы без файлов, а обратного никто не делал.
@Test func orphanOlderThanGraceIsCollectable() {
    let old = file("сирота.png", age: Config.History.orphanBlobGrace + 1)
    #expect(BlobGarbage.collectable(files: [old], referenced: [], now: now) == ["сирота.png"])
}

/// Файл пишется на диск раньше, чем индекс со ссылкой на него, и в этом зазоре
/// он ещё никем не удерживается. Без пощады свежим уборка сносила бы картинку,
/// скопированную только что.
@Test func freshOrphanIsSpared() {
    let fresh = file("только что.png", age: Config.History.orphanBlobGrace - 1)
    #expect(BlobGarbage.collectable(files: [fresh], referenced: [], now: now).isEmpty)
}

@Test func referencedFileIsNeverCollectedNoMatterHowOld() {
    let old = file("нужный.png", age: Config.History.orphanBlobGrace * 1000)
    #expect(BlobGarbage.collectable(files: [old], referenced: ["нужный.png"], now: now).isEmpty)
}

@Test func collectsOnlyTheOrphansAmongMixedFiles() {
    let files = [file("нужный.png", age: 10_000),
                 file("сирота.png", age: 10_000),
                 file("свежая сирота.png", age: 1)]
    #expect(BlobGarbage.collectable(files: files, referenced: ["нужный.png"], now: now)
            == ["сирота.png"])
}
