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
    private let panelState: () -> PanelState
    private let submitActivity: (ActivityEvent) -> Void
    private var lastTrackIdentity: String?
    private var lastPlaying: Bool?

    /// Обложка декодируется один раз на трек, а не при каждом обновлении
    /// позиции — иначе `NSImage(data:)` вызывался бы по несколько раз в
    /// секунду вместе с обновлениями `elapsedTime`. Держит не больше одной
    /// записи: только текущий трек. Прошлые обложки вьюхе уже не нужны, а
    /// накопление их всех за долгую работу приложения было бы утечкой.
    private var artworkCache: [String: NSImage] = [:]

    public init(source: MediaSource,
                panelState: @escaping () -> PanelState,
                submitActivity: @escaping (ActivityEvent) -> Void) {
        self.source = source
        self.panelState = panelState
        self.submitActivity = submitActivity
    }

    /// Замкнутая ссылка на себя в обработчиках — намеренно, а не `[weak self]`.
    /// Замерено: со слабой ссылкой любой тест, что не держит координатор в
    /// отдельной переменной (`let (_, source, events) = make()`), получает
    /// `self == nil` уже к первому `source.emit(...)` — координатор
    /// освобождается сразу после возврата из `make()`, ведь единственная
    /// сильная ссылка на него временно живёт только в возвращаемом кортеже.
    /// Источник и координатор всё равно рассчитаны на связанное время жизни
    /// (владелец создаёт и то, и другое разом на весь срок работы приложения),
    /// так что цикл ссылок здесь не течёт — он рвётся только при завершении
    /// процесса, как и у остальных долгоживущих связок в проекте.
    public func start() {
        source.onState = { s in self.ingest(s) }
        source.onUnavailable = { self.isAvailable = false }
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
            return
        }
        guard artworkCache[identity] == nil else { return }
        guard let data = new.artworkData, let image = NSImage(data: data) else {
            artworkCache = [:]
            return
        }
        artworkCache = [identity: image]
    }

    /// `nonisolated`, потому что тест из брифа зовёт её синхронно без
    /// `@MainActor`: чистая функция от параметра, `self` не трогает, поэтому
    /// изоляция всего класса ей не нужна.
    public nonisolated static func activityEvent(for state: NowPlaying) -> ActivityEvent? {
        guard let title = state.title ?? state.artist else { return nil }
        return ActivityEvent(kind: .track, title: title, subtitle: state.artist)
    }
}
