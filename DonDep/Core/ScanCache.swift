import Foundation

/// Bộ nhớ đệm kết quả phân tích để lần quét sau nhanh hơn rất nhiều.
struct ScanEntry: Codable {
    var mod: Double
    var hash: Data          // 32 byte, rỗng với video
    var blur: Float         // -1 nếu không phân tích
    var brightness: Float
    var size: Int64
}

struct PrintEntry: Codable {
    var mod: Double
    var data: Data
}

struct CacheFile: Codable {
    var version: Int = 1
    var entries: [String: ScanEntry] = [:]
    var prints: [String: PrintEntry] = [:]
}

enum ScanCache {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scan-cache.plist")
    }

    static func load() -> CacheFile {
        guard let data = try? Data(contentsOf: url),
              let file = try? PropertyListDecoder().decode(CacheFile.self, from: data),
              file.version == 1 else { return CacheFile() }
        return file
    }

    static func save(_ file: CacheFile) {
        let enc = PropertyListEncoder()
        enc.outputFormat = .binary
        if let data = try? enc.encode(file) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    static var sizeOnDisk: Int64 {
        let v = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(v?.fileSize ?? 0)
    }
}
