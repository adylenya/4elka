import Testing
import AppKit
@testable import ChelkaCore

private func imageWithText(_ text: String) throws -> URL {
    let size = NSSize(width: 600, height: 140)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    (text as NSString).draw(
        at: NSPoint(x: 20, y: 40),
        withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
    image.unlockFocus()

    let tiff = try #require(image.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ocr-\(UUID().uuidString).png")
    try png.write(to: url)
    return url
}

@Test func russianIsSupportedOnThisMachine() {
    #expect(TextRecognition.supportsRussian())
}

@Test func recognizesLatinText() throws {
    let url = try imageWithText("Hello 4elka")
    let text = try TextRecognition.recognize(imageAt: url)
    #expect(text.localizedCaseInsensitiveContains("hello"))
}

@Test func recognizesCyrillicText() throws {
    let url = try imageWithText("Привет мир")
    let text = try TextRecognition.recognize(imageAt: url)
    #expect(text.localizedCaseInsensitiveContains("привет"))
}

@Test func returnsEmptyStringForBlankImage() throws {
    let url = try imageWithText(" ")
    #expect(try TextRecognition.recognize(imageAt: url).isEmpty)
}

@Test func throwsForMissingFile() {
    #expect(throws: (any Error).self) {
        try TextRecognition.recognize(
            imageAt: URL(fileURLWithPath: "/tmp/нет-такого-\(UUID().uuidString).png"))
    }
}
