import Foundation

/// Где лежит адаптер: скрипт и фреймворк рядом с ним.
public struct AdapterPaths: Equatable, Sendable {
    public let script: URL
    public let framework: URL

    public init(script: URL, framework: URL) {
        self.script = script
        self.framework = framework
    }

    /// Имена, под которыми адаптер лежит и в ресурсах бандла, и в vendor.
    /// Названы, а не рассыпаны по коду: их знают ещё и `scripts/make-app.sh`
    /// с `vendor/build-adapter.sh`, и расходиться им нельзя.
    public static let scriptName = "mediaremote-adapter.pl"
    public static let frameworkName = "MediaRemoteAdapter.framework"
    /// Куда `swift build` кладёт исполняемый файл. По этому имени и опознаётся
    /// запуск из дерева разработки: у установленного приложения такого каталога
    /// в пути нет вовсе.
    public static let buildDirectoryName = ".build"
    /// Где адаптер лежит в дереве разработки.
    public static let vendorScriptPath = "vendor/mediaremote-adapter/bin/\(scriptName)"
    public static let vendorFrameworkPath = "vendor/build/\(frameworkName)"

    /// Адаптер рядом с исполняемым файлом собранного приложения.
    /// `nil` — у бандла нет каталога ресурсов вовсе.
    ///
    /// Существование файлов здесь не проверяется намеренно: этим занимается
    /// `problem()`, и проверка в одном месте не разойдётся с проверкой в другом.
    public static func bundled(resources: URL?) -> AdapterPaths? {
        guard let resources else { return nil }
        return AdapterPaths(script: resources.appendingPathComponent(scriptName),
                            framework: resources.appendingPathComponent(frameworkName))
    }

    public static func bundled(in bundle: Bundle) -> AdapterPaths? {
        bundled(resources: bundle.resourceURL)
    }

    public static func developmentTree(projectRoot: URL) -> AdapterPaths {
        AdapterPaths(script: projectRoot.appendingPathComponent(vendorScriptPath),
                     framework: projectRoot.appendingPathComponent(vendorFrameworkPath))
    }

    /// Корень дерева разработки, выведенный из пути исполняемого файла:
    /// `<корень>/.build/<конфигурация>/Chelka` — три уровня вверх.
    ///
    /// Именно из пути исполняемого файла, а не из текущего каталога процесса:
    /// текущий каталог зависит от того, откуда запустили, и относительный путь
    /// к фреймворку означает мёртвый плеер — perl отказывается его грузить, а
    /// проверка существования файла такой путь как раз разрешит и пропустит.
    ///
    /// `nil`, если путь не абсолютный или это не дерево сборки: у
    /// установленного приложения три уровня вверх дают `/Applications`, и
    /// искать `vendor` там нельзя.
    public static func developmentRoot(executable: URL?) -> URL? {
        guard let executable, executable.path.hasPrefix("/") else { return nil }
        let configuration = executable.deletingLastPathComponent()
        let build = configuration.deletingLastPathComponent()
        guard build.lastPathComponent == buildDirectoryName else { return nil }
        let root = build.deletingLastPathComponent()
        guard root.path.hasPrefix("/") else { return nil }
        return root
    }

    /// Порядок поиска. Бандл первым: установленное приложение не должно
    /// смотреть в чужой рабочий каталог разработчика — на другой машине его нет.
    public static let resolutionOrder: [AdapterSource] = [.bundle, .developmentTree]

    /// Где адаптер лежит на самом деле — или почему его нет.
    ///
    /// Проверка существования файла отдана параметром: так её видно в тесте, и
    /// так она не зависит от того, что сейчас лежит на диске у запускающего.
    public static func locate(bundleResources: URL?,
                              executable: URL?,
                              fileExists: (String) -> Bool = {
                                  FileManager.default.fileExists(atPath: $0)
                              }) -> AdapterLocation {
        var complaint: AdapterPathProblem?
        for source in resolutionOrder {
            let candidate: AdapterPaths?
            switch source {
            case .bundle:
                candidate = bundled(resources: bundleResources)
            case .developmentTree:
                candidate = developmentRoot(executable: executable).map(developmentTree(projectRoot:))
            }
            guard let candidate else { continue }
            guard let problem = candidate.problem(fileExists: fileExists) else {
                return .found(candidate, source)
            }
            // Жалоба берётся от последнего осмотренного кандидата: у
            // установленного приложения это ресурсы бандла, у дерева сборки —
            // vendor, и в обоих случаях это тот путь, куда человеку и надо
            // посмотреть. Общее «нигде не найден» подсказки не даёт.
            complaint = problem
        }
        return .missing(complaint ?? .nowhere)
    }

    /// То же от живого приложения.
    public static func locate(bundle: Bundle = .main) -> AdapterLocation {
        locate(bundleResources: bundle.resourceURL, executable: bundle.executableURL)
    }

    /// Что не так с путями — или `nil`, если всё в порядке.
    ///
    /// Проверка существования файла отдана параметром: так её видно в тесте, и
    /// так она не зависит от того, что сейчас лежит на диске у запускающего.
    public func problem(fileExists: (String) -> Bool = {
        FileManager.default.fileExists(atPath: $0)
    }) -> AdapterPathProblem? {
        // Абсолютность проверяется ПЕРВОЙ и отдельно. Замерено на живой машине:
        // адаптер грузится только по абсолютному пути к фреймворку, с
        // относительным perl падает с «Failed to load framework». А проверка
        // существования относительный путь разрешит от текущего каталога
        // процесса — то есть из дерева сборки файл «найдётся», и поломка
        // прошла бы дальше под видом «поток падает сразу».
        if let relative = [script.path, framework.path].first(where: { !$0.hasPrefix("/") }) {
            return .relativePath(relative)
        }
        // Отсутствующий адаптер даёт коварный случай: сам perl на месте, запуск
        // «удаётся», а процесс умирает мгновенно. Без этой проверки приложение
        // молча дёргало бы его вечно, ни разу не сказав, что плеера нет.
        if !fileExists(script.path) { return .scriptMissing(script.path) }
        if !fileExists(framework.path) { return .frameworkMissing(framework.path) }
        return nil
    }
}

/// Откуда взяты пути к адаптеру.
public enum AdapterSource: Equatable, Sendable {
    /// Ресурсы собранного приложения.
    case bundle
    /// Дерево разработки: `vendor` рядом с `.build`.
    case developmentTree

    /// Как это называется в логе. Строчка «адаптер взят из developmentTree»
    /// написана не для человека, а для компилятора.
    public var title: String {
        switch self {
        case .bundle: return "ресурсов приложения"
        case .developmentTree: return "дерева разработки"
        }
    }
}

/// Итог поиска адаптера. Отказ обязан назвать причину: плеер, умирающий молча,
/// выглядит как «иногда не работает», и таким он и был.
public enum AdapterLocation: Equatable, Sendable {
    case found(AdapterPaths, AdapterSource)
    case missing(AdapterPathProblem)

    public var paths: AdapterPaths? {
        guard case .found(let paths, _) = self else { return nil }
        return paths
    }

    public var problem: AdapterPathProblem? {
        guard case .missing(let problem) = self else { return nil }
        return problem
    }
}

/// Беда с путями к адаптеру, сформулированная так, чтобы строчку в логе можно
/// было прочитать и понять, что делать.
public enum AdapterPathProblem: Equatable, Sendable {
    /// Путь не абсолютный. Отдельный случай, а не «не найден»: файл по такому
    /// пути как раз найдётся — от текущего каталога процесса, — а perl потом
    /// откажется грузить фреймворк, и причина будет выглядеть как случайный
    /// обрыв потока.
    case relativePath(String)
    case scriptMissing(String)
    case frameworkMissing(String)
    /// Искать негде: ни ресурсов бандла, ни дерева сборки.
    case nowhere

    public var message: String {
        switch self {
        case .relativePath(let path):
            return "путь к адаптеру плеера не абсолютный, perl не сможет загрузить фреймворк: \(path)"
        case .scriptMissing(let path):
            return "скрипт адаптера плеера не найден: \(path)"
        case .frameworkMissing(let path):
            return "фреймворк адаптера плеера не найден (не собран?): \(path)"
        case .nowhere:
            return "адаптер плеера не найден ни в ресурсах приложения, ни в дереве сборки"
        }
    }
}
