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
    #expect(!AdapterPathProblem.nowhere.message.isEmpty)
}

// MARK: - Откуда берётся корень дерева разработки

/// Корень выводится из АБСОЛЮТНОГО пути исполняемого файла — три уровня вверх
/// от `.build/<конфигурация>/Chelka`. Не из текущего каталога процесса: тот
/// зависит от того, откуда запустили, и на живой машине именно относительный
/// путь оставлял плеер мёртвым молча.
@Test func developmentRootIsThreeLevelsAboveTheBuiltExecutable() {
    let root = AdapterPaths.developmentRoot(
        executable: URL(fileURLWithPath: "/Users/x/4elka/.build/debug/Chelka"))
    #expect(root?.path == "/Users/x/4elka")
    #expect(AdapterPaths.developmentRoot(
        executable: URL(fileURLWithPath: "/Users/x/4elka/.build/release/Chelka"))?.path
        == "/Users/x/4elka")
}

/// Относительный путь корнем быть не может: `problem()` его не поймает, потому
/// что файл по нему как раз «найдётся» — от текущего каталога процесса.
@Test func relativeExecutableGivesNoDevelopmentRootAtAll() {
    #expect(AdapterPaths.developmentRoot(executable: URL(string: ".build/debug/Chelka")) == nil)
    #expect(AdapterPaths.developmentRoot(executable: nil) == nil)
}

/// Установленное приложение дерева разработки не имеет: три уровня вверх от
/// `/Applications/4elka.app/Contents/MacOS/Chelka` — это `/Applications`, и
/// искать там `vendor` нельзя. Иначе отказ выглядел бы как «фреймворк не
/// найден в /Applications/vendor», то есть как поломка вместо «его тут и нет».
@Test func installedAppHasNoDevelopmentTree() {
    #expect(AdapterPaths.developmentRoot(
        executable: URL(fileURLWithPath: "/Applications/4elka.app/Contents/MacOS/Chelka")) == nil)
}

// MARK: - Порядок разрешения путей

@Test func resolutionLooksInTheBundleBeforeTheDevelopmentTree() {
    #expect(AdapterPaths.resolutionOrder == [.bundle, .developmentTree])
}

/// Оба места на диске есть — берётся бандл: установленное приложение не должно
/// смотреть в чужой рабочий каталог, которого на другой машине нет.
@Test func bundleWinsOverDevelopmentTreeWhenBothExist() {
    let location = AdapterPaths.locate(
        bundleResources: URL(fileURLWithPath: "/Applications/4elka.app/Contents/Resources"),
        executable: URL(fileURLWithPath: "/Users/x/4elka/.build/debug/Chelka"),
        fileExists: { _ in true })
    guard case .found(let paths, let source) = location else {
        Issue.record("адаптер не найден, хотя лежит в обоих местах")
        return
    }
    #expect(source == .bundle)
    #expect(paths.script.path
            == "/Applications/4elka.app/Contents/Resources/mediaremote-adapter.pl")
}

/// В бандле адаптера нет (запуск из дерева сборки) — берём vendor.
@Test func developmentTreeIsUsedWhenTheBundleHasNoAdapter() {
    let location = AdapterPaths.locate(
        bundleResources: URL(fileURLWithPath: "/Users/x/4elka/.build/debug"),
        executable: URL(fileURLWithPath: "/Users/x/4elka/.build/debug/Chelka"),
        fileExists: { $0.hasPrefix("/Users/x/4elka/vendor") })
    guard case .found(let paths, let source) = location else {
        Issue.record("адаптер в дереве разработки не найден")
        return
    }
    #expect(source == .developmentTree)
    #expect(paths.script.path.hasPrefix("/Users/x/4elka/vendor"))
}

/// Что нашли — то обязано быть годным к запуску: абсолютным и существующим.
/// «Нашли» с негодными путями означало бы, что perl попробует и молча умрёт.
@Test func foundPathsAreAlwaysFitToLaunch() {
    let location = AdapterPaths.locate(
        bundleResources: URL(fileURLWithPath: "/Applications/4elka.app/Contents/Resources"),
        executable: URL(fileURLWithPath: "/Users/x/4elka/.build/debug/Chelka"),
        fileExists: { _ in true })
    guard case .found(let paths, _) = location else {
        Issue.record("адаптер не найден")
        return
    }
    #expect(paths.problem(fileExists: { _ in true }) == nil)
}

/// Адаптера нет нигде — отказ обязан НАЗВАТЬ причину. Молчаливая смерть плеера
/// уже была дефектом: подсистема живая, а в панели пусто и в логе ни строчки.
@Test func missingAdapterAlwaysNamesTheReason() {
    let nothing = AdapterPaths.locate(bundleResources: nil, executable: nil,
                                      fileExists: { _ in false })
    guard case .missing(let problem) = nothing else {
        Issue.record("адаптер «нашёлся» там, где его нет")
        return
    }
    #expect(!problem.message.isEmpty)
}

/// Фреймворк не собран (`make adapter` не запускали) — жалоба обязана назвать
/// именно его, а не общее «нигде не найден»: это единственная подсказка о том,
/// что делать дальше.
@Test func unbuiltFrameworkIsNamedInsteadOfAGenericRefusal() {
    let location = AdapterPaths.locate(
        bundleResources: nil,
        executable: URL(fileURLWithPath: "/Users/x/4elka/.build/debug/Chelka"),
        fileExists: { $0.hasSuffix(".pl") })
    guard case .missing(let problem) = location else {
        Issue.record("пути без фреймворка признаны годными")
        return
    }
    #expect(problem == .frameworkMissing("/Users/x/4elka/vendor/build/MediaRemoteAdapter.framework"))
}
