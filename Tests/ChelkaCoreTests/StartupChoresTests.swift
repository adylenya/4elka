import Testing
import Foundation
@testable import ChelkaCore

/// Уборка временного каталога жеста звалась только в начале следующего жеста.
/// Человек один раз вытащил двадцать картинок, закрыл приложение и неделю не
/// перетаскивал — файлы старше часа, а убирать их некому.
@Test func startupSweepsStaleDragFilesLeftFromPreviousRun() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-startup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let now = Date()
    let stale = root.appendingPathComponent("прошлый запуск.png")
    let fresh = root.appendingPathComponent("этот запуск.png")
    for url in [stale, fresh] { try Data("x".utf8).write(to: url) }
    try FileManager.default.setAttributes(
        [.modificationDate: now.addingTimeInterval(-Config.Drag.tempLifetime - 60)],
        ofItemAtPath: stale.path)

    StartupChores.run(dragTemp: root, now: now)

    #expect(FileManager.default.fileExists(atPath: stale.path) == false)
    #expect(FileManager.default.fileExists(atPath: fresh.path))
}

/// Каталога может не быть вовсе — до первого перетаскивания его не существует.
/// Старт приложения об это спотыкаться не должен.
@Test func startupChoresSurviveMissingDragDirectory() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-startup-нет-\(UUID().uuidString)")
    StartupChores.run(dragTemp: root, now: Date())
    #expect(FileManager.default.fileExists(atPath: root.path) == false)
}
