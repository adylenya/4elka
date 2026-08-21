import Foundation

/// Готовит файлы для перетаскивания наружу: копии блобов с человеческими именами.
/// Так удаётся обойтись обычными файловыми ссылками вместо обещаний файлов.
public struct DragMaterializer {
    private let root: URL
    private let fm = FileManager.default

    public init(root: URL) { self.root = root }

    public func materialize(blob: URL, displayName: String) throws -> URL {
        let name = Self.safeFileName(displayName, extension: blob.pathExtension)
        let dest = try uniqueURL(for: name)
        try fm.copyItem(at: blob, to: dest)
        return dest
    }

    public func materialize(text: String, displayName: String) throws -> URL {
        let name = Self.safeFileName(displayName, extension: "txt")
        let dest = try uniqueURL(for: name)
        try Data(text.utf8).write(to: dest)
        return dest
    }

    public static func safeFileName(_ raw: String, extension ext: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = raw.components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty || cleaned.allSatisfy { $0 == "-" } ? "фрагмент" : cleaned
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    private func uniqueURL(for name: String) throws -> URL {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let candidate = root.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        for i in 2...999 {
            let next = root.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            if !fm.fileExists(atPath: next.path) { return next }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
