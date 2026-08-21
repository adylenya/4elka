import Testing
import Foundation
@testable import ChelkaCore

/// Проверки описания бандла. Смысл в том, чтобы описание не разошлось с кодом:
/// это единственная пара «файл на диске и константа в коде», которую ничто
/// другое не сверяет, а расхождение проявится только на чужой машине.
private var repositoryRoot: URL {
    // От файла теста вверх: Tests/ChelkaCoreTests/<файл>.
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func bundleDescription() throws -> [String: Any] {
    let url = repositoryRoot.appendingPathComponent("Resources/Info.plist")
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    return plist as? [String: Any] ?? [:]
}

@Test func bundleIdentifierMatchesTheOneCodeIgnoresItselfBy() throws {
    // По этому идентификатору приложение узнаёт свою собственную запись в буфер.
    // Разойдутся — и приложение начнёт складывать в историю то, что само же
    // туда и положило.
    let plist = try bundleDescription()
    #expect(plist["CFBundleIdentifier"] as? String == Config.ownBundleID)
}

@Test func minimumSystemVersionMatchesWhatCodeActuallyNeeds() throws {
    // Интерфейс построен на системном «жидком стекле», которого нет до macOS 26.
    // Занизить эту цифру — значит разрешить установку туда, где приложение
    // не запустится, и человек увидит не понятный отказ, а падение.
    let plist = try bundleDescription()
    let raw = plist["LSMinimumSystemVersion"] as? String ?? ""
    let major = Int(raw.split(separator: ".").first.map(String.init) ?? "") ?? 0
    #expect(major >= 26, "в описании бандла указано \(raw)")
}

@Test func bundleHidesItselfFromTheDock() throws {
    // Иконки в доке быть не должно: приложение живёт в челке и в строке меню.
    // Без этого флага у него появится иконка, а окна у него нет — получится
    // приложение, которое нечем закрыть, кроме принудительного завершения.
    let plist = try bundleDescription()
    #expect(plist["LSUIElement"] as? Bool == true)
}

@Test func bundleExecutableNameMatchesTheProduct() throws {
    // Имя модуля Swift не может начинаться с цифры, поэтому продукт называется
    // 4elka.app, а исполняемый файл внутри — Chelka. Перепутать легко.
    let plist = try bundleDescription()
    #expect(plist["CFBundleExecutable"] as? String == "Chelka")
}
