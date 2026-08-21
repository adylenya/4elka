import AppKit
import Foundation

public struct CaptureResult: Equatable {
    /// Почему элемент не попал в историю. «Отказались по правилу» и «не смогли
    /// записать на диск» — разные вещи, и раньше они были неотличимы: оба давали
    /// пустой результат, и понять, наше это решение или сбой, было нельзя.
    public enum Skip: Equatable {
        case ignored(IgnoreDecision.Reason)
        case nothingUsable
        case storageFailed
    }

    public let store: HistoryStore
    public let inserted: ClipItem?
    public let evictedBlobNames: [String]
    public let skip: Skip?
}

public struct ClipboardCapture {
    private let rules: IgnoreRules
    private let blobs: BlobStore

    public init(rules: IgnoreRules, blobs: BlobStore) {
        self.rules = rules
        self.blobs = blobs
    }

    public func capture(_ snapshot: PasteboardSnapshot,
                        into store: HistoryStore,
                        now: Date) -> CaptureResult {
        let decision = rules.decide(types: snapshot.types,
                                    sourceBundleID: snapshot.sourceBundleID,
                                    byteCount: snapshot.byteCount)
        if let reason = decision.reason {
            return CaptureResult(store: store, inserted: nil, evictedBlobNames: [],
                                 skip: .ignored(reason))
        }
        guard let kind = makeKind(snapshot) else {
            return CaptureResult(store: store, inserted: nil, evictedBlobNames: [],
                                 skip: lastMakeKindFailedOnStorage ? .storageFailed : .nothingUsable)
        }

        let item = ClipItem(id: UUID(), kind: kind,
                            sourceAppBundleID: snapshot.sourceBundleID,
                            createdAt: now,
                            contentHash: hash(for: snapshot, kind: kind),
                            isPinned: false)
        let next = store.inserting(item)
        return CaptureResult(store: next,
                             inserted: item,
                             evictedBlobNames: next.evictedBlobNames(comparedTo: store),
                             skip: nil)
    }

    /// Отличить «нечего сохранять» от «диск отказал». Захват — структура, поэтому
    /// признак держим в классе-обёртке, а не мутируем себя.
    private final class StorageFailureFlag { var failed = false }
    private let storageFailure = StorageFailureFlag()
    private var lastMakeKindFailedOnStorage: Bool { storageFailure.failed }

    private func makeKind(_ s: PasteboardSnapshot) -> ClipItem.Kind? {
        storageFailure.failed = false
        if let data = s.imageData, let ext = s.imageExtension {
            let name: String
            do {
                name = try blobs.write(data, extension: ext)
            } catch {
                // Молчать нельзя: снаружи это выглядело бы точно так же, как
                // «мы сами решили не сохранять», и сбой диска остался бы незаметным.
                NSLog("4elka: не удалось записать картинку из буфера: %@",
                      String(describing: error))
                storageFailure.failed = true
                return nil
            }
            let size = NSImage(data: data)?.size ?? .zero
            return .image(.init(blobName: name, byteCount: data.count, pixelSize: size))
        }
        if !s.fileURLs.isEmpty { return .files(s.fileURLs) }
        if let text = s.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        return nil
    }

    private func hash(for s: PasteboardSnapshot, kind: ClipItem.Kind) -> String {
        switch kind {
        case .text(let t): return Hashing.sha256(Data(t.utf8))
        case .image: return Hashing.sha256(s.imageData ?? Data())
        case .files(let urls): return Hashing.sha256(Data(urls.map(\.path).joined(separator: "\n").utf8))
        }
    }
}

/// Опрос вместо подписки: уведомлений об изменении буфера в macOS нет.
///
/// Класс целиком на главном акторе, и это осознанно. Предыдущая версия жила на
/// своей очереди с ручным обещанием потокобезопасности — и обещание оказалось
/// правдой лишь для одного поля из трёх: таймер и публичное замыкание писались
/// с произвольного потока. Проверка `changeCount` стоит копейки, а данные читаются
/// только когда он изменился, поэтому главный актор здесь ничего не тормозит
/// и убирает целый класс ошибок вместо того, чтобы прятать его от компилятора.
@MainActor
public final class PasteboardWatcher {
    private let reader: PasteboardReading
    /// `nil` значит «ещё не опрашивали ни разу». Опрос до первого реального такта
    /// не выполняется, поэтому нет отдельного «текущего» значения на момент
    /// создания наблюдателя, которое можно было бы прочитать заранее и от него
    /// отталкиваться — значение появляется только внутри `pollOnce()`.
    private var lastChangeCount: Int?
    /// Таймер опроса. Открыт для чтения внутри модуля не ради удобства: иначе
    /// «повторный `start()` не заводит второй таймер» проверить нечем, а без
    /// проверки тест на это оставался зелёным даже без самой защиты.
    private(set) var timer: Timer?
    /// Номер записи, сделанной нами самими. Определять «своё» по тому, какое
    /// приложение сейчас впереди, нельзя: вопрос задаётся до 200 мс спустя после
    /// записи, за это время впереди может оказаться кто угодно, и наша же запись
    /// прошла бы в историю — тот самый бесконечный цикл. Номер записи не врёт.
    private var selfWriteChangeCount: Int?

    public var onChange: ((PasteboardSnapshot) -> Void)?

    public init(reader: PasteboardReading = SystemPasteboard()) {
        self.reader = reader
    }

    /// Сообщить, что запись с этим номером сделали мы. Возвращаемый номер даёт
    /// `NSPasteboard.clearContents()`.
    public func ignoreSelfWrite(changeCount: Int) {
        selfWriteChangeCount = changeCount
    }

    public func start() {
        // Без этой проверки повторный вызов оставлял бы два живых таймера,
        // опрашивающих один и тот же буфер.
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Config.History.pollInterval,
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Один такт опроса. Открыт наружу, чтобы тест мог прогнать его без таймера.
    public func pollOnce() {
        let snapshot = reader.snapshot()
        guard snapshot.changeCount != lastChangeCount else { return }
        lastChangeCount = snapshot.changeCount
        if snapshot.changeCount == selfWriteChangeCount {
            selfWriteChangeCount = nil
            return
        }
        onChange?(snapshot)
    }
}
