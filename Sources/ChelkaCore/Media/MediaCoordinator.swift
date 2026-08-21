import AppKit
import Foundation

/// Сшивает поток `MediaSource` с общей очередью выезжающих карточек.
///
/// Главное правило: карточка выезжает на смену трека и на пауза/плей, но не на
/// обновление позиции. Замерено на живой фикстуре — `contentItemIdentifier` в
/// потоке меняется при каждом обновлении состояния, а не при смене трека, за
/// одну песню он сменился трижды. Поэтому идентичность трека — это
/// `NowPlaying.trackIdentity` (название плюс исполнитель), а не поле потока.
/// Если раздать карточку на каждое обновление позиции, она будет выскакивать
/// каждые несколько секунд у играющей музыки.
@MainActor
public final class MediaCoordinator: ObservableObject {
    @Published public private(set) var state = NowPlaying.empty
    @Published public private(set) var isAvailable = true

    private let source: MediaSource
    private let submitActivity: (ActivityEvent) -> Void
    private var lastTrackIdentity: String?
    private var lastPlaying: Bool?

    /// Обложка декодируется один раз на трек, а не при каждом обновлении
    /// позиции — иначе `NSImage(data:)` вызывался бы по несколько раз в
    /// секунду вместе с обновлениями `elapsedTime`. Держит не больше одной
    /// записи: только текущий трек. Прошлые обложки вьюхе уже не нужны, а
    /// накопление их всех за долгую работу приложения было бы утечкой.
    private var artworkCache: [String: NSImage] = [:]

    /// Идентичность, для которой обложка уже не разобралась. Без этой памяти
    /// один и тот же битый мегабайт разбирался бы заново на каждом обновлении
    /// позиции — то есть раз в секунду у играющего трека.
    private var failedArtworkIdentity: String?

    /// Разбор картинки — параметром, а не жёстко `NSImage(data:)`: иначе
    /// «разобрали один раз, а не двадцать» нечем проверить тестом.
    private let decodeArtwork: (Data) -> NSImage?

    /// Состояния панели здесь нет намеренно: координатор его не читал ни разу,
    /// а поле, которое только присваивают, следующий читатель принимает за
    /// работающую логику и строит на нём решения. Кому нужно знать, раскрыта ли
    /// панель (например, полосе позиции), тот получает это состояние сам.
    public init(source: MediaSource,
                submitActivity: @escaping (ActivityEvent) -> Void,
                decodeArtwork: @escaping (Data) -> NSImage? = { NSImage(data: $0) }) {
        self.source = source
        self.submitActivity = submitActivity
        self.decodeArtwork = decodeArtwork
    }

    /// Захват слабый. Сильный убрал бы возможность проверить, что освобождённый
    /// координатор перестаёт получать события: цикл ссылок держал бы его вечно.
    /// Владелец обязан хранить координатор сам — тест тоже.
    public func start() {
        source.onState = { [weak self] s in self?.ingest(s) }
        source.onUnavailable = { [weak self] in self?.isAvailable = false }
        source.start()
    }

    public func send(_ command: MediaCommand) { source.send(command) }

    /// Обложка текущего трека, если она уже декодирована и закэширована.
    /// `nil`, пока данных нет или ничего не играет — вьюха в этом случае
    /// показывает заглушку, а не пустое место.
    public var artwork: NSImage? {
        guard let identity = state.trackIdentity else { return nil }
        return artworkCache[identity]
    }

    private func ingest(_ new: NowPlaying) {
        state = new
        updateArtworkCache(for: new)

        guard !new.isEmpty else {
            lastTrackIdentity = nil
            lastPlaying = nil
            return
        }
        let trackChanged = new.trackIdentity != lastTrackIdentity
        let playingChanged = new.isPlaying != lastPlaying
        lastTrackIdentity = new.trackIdentity
        lastPlaying = new.isPlaying

        guard trackChanged || playingChanged, let event = Self.activityEvent(for: new) else { return }
        submitActivity(event)
    }

    /// Держит кэш ровно из 0 или 1 записи — записи текущего трека. Свежий
    /// трек без ещё пришедших данных обложки чистит кэш немедленно, а не
    /// ждёт: старая картинка не относится к новому треку, показывать её было
    /// бы обманом.
    private func updateArtworkCache(for new: NowPlaying) {
        guard let identity = new.trackIdentity else {
            artworkCache = [:]
            failedArtworkIdentity = nil
            return
        }
        guard artworkCache[identity] == nil else { return }
        // Разбор этой обложки уже провалился — второй раз он провалится так же,
        // а стоит это разбора мегабайта на каждое обновление позиции.
        guard failedArtworkIdentity != identity else { return }
        guard let data = new.artworkData else {
            artworkCache = [:]
            return
        }
        guard let image = decodeArtwork(data) else {
            NSLog("4elka: обложка трека не разобралась (%d байт), больше не пробую", data.count)
            artworkCache = [:]
            failedArtworkIdentity = identity
            return
        }
        artworkCache = [identity: image]
        failedArtworkIdentity = nil
    }

    /// `nonisolated`, потому что тест из брифа зовёт её синхронно без
    /// `@MainActor`: чистая функция от параметра, `self` не трогает, поэтому
    /// изоляция всего класса ей не нужна.
    public nonisolated static func activityEvent(for state: NowPlaying) -> ActivityEvent? {
        // Обе строки берутся из `displayLines`: пустая первая строка читается как
        // поломка, а исполнитель, стоящий одновременно заголовком и
        // подзаголовком, — как ошибка отрисовки.
        guard let lines = state.displayLines else { return nil }
        return ActivityEvent(kind: .track, title: lines.headline, subtitle: lines.subheadline)
    }
}
