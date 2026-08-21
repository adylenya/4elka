import Testing
import Foundation
@testable import ChelkaCore

private func tempRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func materializesBlobUnderHumanReadableName() throws {
    let root = tempRoot()
    let blob = root.appendingPathComponent("2b7f.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: blob)

    let m = DragMaterializer(root: root.appendingPathComponent("out"))
    let url = try m.materialize(blob: blob, displayName: "Снимок 2026-08-21 15-48")

    #expect(url.lastPathComponent == "Снимок 2026-08-21 15-48.png")
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(try Data(contentsOf: url) == Data([0x89, 0x50, 0x4E, 0x47]))
}

@Test func materializesTextAsUtf8File() throws {
    let m = DragMaterializer(root: tempRoot())
    let url = try m.materialize(text: "привет", displayName: "фрагмент")
    #expect(url.lastPathComponent == "фрагмент.txt")
    #expect(try String(contentsOf: url, encoding: .utf8) == "привет")
}

@Test func replacesCharactersIllegalInFileNames() {
    #expect(DragMaterializer.safeFileName("a/b:c", extension: "png") == "a-b-c.png")
}

@Test func fallsBackWhenNameIsEmptyAfterCleaning() {
    #expect(DragMaterializer.safeFileName("///", extension: "txt") == "фрагмент.txt")
}

@Test func doesNotOverwriteExistingFileWithSameName() throws {
    let root = tempRoot()
    let m = DragMaterializer(root: root)
    let a = try m.materialize(text: "один", displayName: "имя")
    let b = try m.materialize(text: "два", displayName: "имя")
    #expect(a != b)
    #expect(try String(contentsOf: a, encoding: .utf8) == "один")
    #expect(try String(contentsOf: b, encoding: .utf8) == "два")
}
