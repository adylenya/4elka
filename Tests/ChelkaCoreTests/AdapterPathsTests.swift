import Testing
import Foundation
@testable import ChelkaCore

/// Замерено на живой машине: адаптер грузится ТОЛЬКО по абсолютному пути к
/// фреймворку — с относительным perl падает с «Failed to load framework».
/// Проверка существования файла при этом относительный путь разрешает от
/// текущего каталога процесса: файл «находится», и поломка проходит дальше.
@Test func relativePathIsAProblemEvenWhenTheFileWouldBeFound() {
    let paths = AdapterPaths(script: URL(string: "vendor/mediaremote-adapter.pl")!,
                             framework: URL(string: "vendor/MediaRemoteAdapter.framework")!)
    #expect(paths.problem(fileExists: { _ in true })
            == .relativePath("vendor/mediaremote-adapter.pl"))
}

@Test func missingScriptAndMissingFrameworkAreNamedSeparately() {
    let paths = AdapterPaths(script: URL(fileURLWithPath: "/tmp/чего-то.pl"),
                             framework: URL(fileURLWithPath: "/tmp/чего-то.framework"))
    #expect(paths.problem(fileExists: { _ in false }) == .scriptMissing("/tmp/чего-то.pl"))
    #expect(paths.problem(fileExists: { $0.hasSuffix(".pl") })
            == .frameworkMissing("/tmp/чего-то.framework"))
}

@Test func absoluteAndExistingPathsHaveNoProblem() {
    let paths = AdapterPaths.developmentTree(projectRoot: URL(fileURLWithPath: "/Users/x/4elka"))
    #expect(paths.problem(fileExists: { _ in true }) == nil)
}

/// Сообщение обязано объяснять человеку, что именно не так: одной строки
/// «поток падает сразу, прекращаю попытки» для этого не хватало.
@Test func problemMessagesNameThePathAndTheReason() {
    #expect(AdapterPathProblem.relativePath("vendor/a.pl").message.contains("vendor/a.pl"))
    #expect(AdapterPathProblem.relativePath("vendor/a.pl").message.contains("абсолютн"))
    #expect(AdapterPathProblem.scriptMissing("/tmp/a.pl").message.contains("/tmp/a.pl"))
    #expect(AdapterPathProblem.frameworkMissing("/tmp/f").message.contains("/tmp/f"))
}
