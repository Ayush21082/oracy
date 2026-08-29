import Foundation

/// Persists session audio on disk for History playback (mock + local cache).
enum LocalAudioStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Oracy/Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(sessionId: UUID) -> URL {
        directory.appendingPathComponent("\(sessionId.uuidString).m4a")
    }

    static func save(from source: URL, sessionId: UUID) throws -> String {
        let dest = fileURL(sessionId: sessionId)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest.path
    }

    static func urlIfExists(sessionId: UUID) -> URL? {
        let url = fileURL(sessionId: sessionId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func url(forStoredPath path: String?, sessionId: UUID) -> URL? {
        if let local = urlIfExists(sessionId: sessionId) {
            return local
        }
        guard let path, !path.isEmpty else { return nil }
        // Absolute path from mock save
        if path.hasPrefix("/") {
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return nil
    }

    static func delete(sessionId: UUID) {
        let url = fileURL(sessionId: sessionId)
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
