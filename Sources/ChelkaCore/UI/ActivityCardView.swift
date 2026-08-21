import SwiftUI

public struct ActivityCardView: View {
    public let event: ActivityEvent
    public let blobs: BlobStore

    public init(event: ActivityEvent, blobs: BlobStore) {
        self.event = event
        self.blobs = blobs
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let name = event.imageBlobName,
               let image = NSImage(contentsOf: blobs.url(for: name)) {
                Image(nsImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: icon).font(.system(size: 16)).frame(width: 34)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let s = event.subtitle {
                    Text(s).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: String {
        switch event.kind {
        case .track: return "music.note"
        case .clipboard: return "doc.on.clipboard"
        case .battery: return "battery.25"
        }
    }
}
