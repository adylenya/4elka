import Testing
import Foundation
@testable import ChelkaCore

/// Обращение к нулевому элементу списка каталогов роняло приложение на старте,
/// если система вернула пустой список. Падать здесь нельзя ни при каком ответе
/// системы: без каталога данных приложение просто не запустится, и человек не
/// поймёт, почему.
@Test func supportBaseFallsBackToHomeWhenSystemNamesNoDirectory() {
    let home = URL(fileURLWithPath: "/Users/кто-то", isDirectory: true)
    let base = AppPaths.supportBase(candidates: [], home: home)
    #expect(base.path == "/Users/кто-то/Library/Application Support")
}

@Test func supportBaseTakesTheFirstDirectorySystemNames() {
    let first = URL(fileURLWithPath: "/Users/кто-то/Library/Application Support", isDirectory: true)
    let second = URL(fileURLWithPath: "/Library/Application Support", isDirectory: true)
    #expect(AppPaths.supportBase(candidates: [first, second],
                                 home: URL(fileURLWithPath: "/")) == first)
}

@Test func historyFilesLiveInsideOwnDirectory() {
    #expect(AppPaths.index.deletingLastPathComponent().lastPathComponent == "4elka")
    #expect(AppPaths.blobs.lastPathComponent == "blobs")
}
