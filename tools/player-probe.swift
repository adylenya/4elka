// Пробник плеера: читает «сейчас играет» настоящими частями приложения и
// считает, сколько карточек выехало бы за 45 секунд. Только чтение — команды
// плееру не посылаются, музыка не прерывается, окна не рисуются.
//
// Зачем нужен. Проверка «полминуты не трогать играющий трек — карточка не должна
// выехать ни разу» иначе недостоверна: если музыка стоит на паузе, поток молчит,
// карточек ноль, и это ничего не доказывает. Поэтому состояние воспроизведения
// снимается до и после замера и печатается рядом с итогом.
//
// Запуск: make probe-player
// Осмысленный результат только при играющей музыке («играет true» в обеих
// строках снимка).

import AppKit
import Foundation

// Честный замер мигания карточки. Ничего не подменяем: слушаем только то, что
// координатор отдаёт наружу. Состояние воспроизведения снимаем до и после —
// прошлый замер был недостоверен именно потому, что этого не делал.
// Корень берём от каталога запуска (`make` запускает из корня репозитория), но
// обязательно АБСОЛЮТНЫМ: замерено на живой машине — perl грузит фреймворк
// адаптера только по абсолютному пути, с относительным падает с «Failed to load
// framework». `currentDirectoryPath` абсолютен всегда.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let paths = AdapterPaths.developmentTree(projectRoot: root)
if let problem = paths.problem() { print("пути к адаптеру: \(problem.message)"); exit(2) }

/// Возвращает, играло ли в этот момент: от этого зависит, значит ли замер
/// хоть что-нибудь.
@discardableResult
func snapshot(_ label: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    p.arguments = [paths.script.path, paths.framework.path, "get"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("\(label): плеер молчит")
        return false
    }
    let title = json["title"] as? String ?? "—"
    let playing = json["playing"] as? Bool ?? false
    let elapsed = Int((json["elapsedTime"] as? Double) ?? 0)
    print("\(label): «\(title)», играет \(playing), позиция \(elapsed) с")
    return playing
}

final class Box: @unchecked Sendable { var cards: [(TimeInterval, String)] = [] }
let box = Box()
let started = Date()

let playingBefore = snapshot("до замера")

MainActor.assumeIsolated {
    let bridge = MediaRemoteBridge(paths: paths)
    let coordinator = MediaCoordinator(
        source: bridge,
        submitActivity: { e in
            let t = Date().timeIntervalSince(started)
            box.cards.append((t, e.title))
            print(String(format: "  %.1f с — КАРТОЧКА: %@", t, e.title))
        })
    coordinator.start()

    Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { _ in
        let playingAfter = snapshot("после замера")
        print("--- итог за 45 секунд ---")
        print("карточек: \(box.cards.count)")
        // Пауза делает замер бессмысленным: поток молчит, карточек ноль, и это
        // ничего не говорит о мигании. Такой итог обязан называться
        // недостоверным, иначе он попадёт в отчёт как доказательство — так уже
        // однажды и вышло.
        guard playingBefore, playingAfter else {
            print("ЗАМЕР НЕДОСТОВЕРЕН: музыка не играла всё время замера.")
            print("Включи музыку и запусти снова: make probe-player")
            exit(1)
        }
        print(box.cards.count <= 1
              ? "ВЕРНО: карточка не мигает — не больше одной (первое появление трека)."
              : "ПРОБЛЕМА: карточка выехала \(box.cards.count) раз при нетронутом треке.")
        exit(0)
    }
}
RunLoop.main.run()
