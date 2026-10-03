import Foundation

/// Stores API responses as files so finished weeks are downloaded once.
public final class DiskCache: @unchecked Sendable {
    private let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL? = nil) {
        let base = directory ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SleeperCache", isDirectory: true)
        self.directory = base
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func fileURL(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }

    /// Returns cached data if it exists and is younger than `maxAge` (nil means any age).
    public func read(_ key: String, maxAge: TimeInterval?) -> Data? {
        let url = fileURL(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let maxAge {
            let modified = (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
            if Date().timeIntervalSince(modified) > maxAge { return nil }
        }
        return data
    }

    public func write(_ key: String, data: Data) {
        try? data.write(to: fileURL(key), options: .atomic)
    }

    public func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
