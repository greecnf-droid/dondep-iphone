import Foundation
import Photos
import SwiftUI

// MARK: - Danh mục dọn dẹp

enum CleanCategory: String, CaseIterable, Identifiable, Hashable {
    case duplicates, similar, bursts, screenshots, livePhotos, blurry, largeVideos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicates: return "Ảnh trùng lặp"
        case .similar: return "Ảnh tương tự"
        case .bursts: return "Ảnh chụp liên tiếp"
        case .screenshots: return "Ảnh chụp màn hình"
        case .livePhotos: return "Ảnh Live"
        case .blurry: return "Ảnh mờ & tối"
        case .largeVideos: return "Video dung lượng lớn"
        }
    }

    var subtitle: String {
        switch self {
        case .duplicates: return "Giống hệt nhau, giữ lại 1 bản tốt nhất"
        case .similar: return "Chụp nhiều kiểu gần giống nhau"
        case .bursts: return "Các khung hình burst không được chọn"
        case .screenshots: return "Thường không cần giữ lâu"
        case .livePhotos: return "Chuyển sang ảnh tĩnh để tiết kiệm ~50%"
        case .blurry: return "Bị nhòe, rung tay hoặc quá tối"
        case .largeVideos: return "Video chiếm nhiều dung lượng nhất"
        }
    }

    var icon: String {
        switch self {
        case .duplicates: return "square.on.square"
        case .similar: return "photo.stack"
        case .bursts: return "square.stack.3d.down.right"
        case .screenshots: return "camera.viewfinder"
        case .livePhotos: return "livephoto"
        case .blurry: return "eye.slash"
        case .largeVideos: return "film"
        }
    }

    var color: Color {
        switch self {
        case .duplicates: return .red
        case .similar: return .orange
        case .bursts: return .pink
        case .screenshots: return .blue
        case .livePhotos: return .yellow
        case .blurry: return .purple
        case .largeVideos: return .green
        }
    }

    var isGrouped: Bool {
        switch self {
        case .duplicates, .similar, .bursts: return true
        default: return false
        }
    }
}

// MARK: - Nhóm ảnh

struct AssetGroup: Identifiable {
    let id: String
    var assets: [PHAsset]

    init(_ assets: [PHAsset]) {
        self.assets = assets
        self.id = assets.first?.localIdentifier ?? UUID().uuidString
    }
}

struct IdentifiedAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

// MARK: - Kết quả quét

struct ScanResult {
    var duplicateGroups: [AssetGroup] = []
    var similarGroups: [AssetGroup] = []
    var burstGroups: [AssetGroup] = []
    var screenshots: [PHAsset] = []
    var livePhotos: [PHAsset] = []
    var blurry: [PHAsset] = []
    var largeVideos: [PHAsset] = []
    var allVideos: [PHAsset] = []
    var sizes: [String: Int64] = [:]
    var blurScores: [String: Float] = [:]
    var totalPhotos = 0
    var totalVideos = 0
    var totalBytes: Int64 = 0
    var skippedCloud = 0
    var date = Date()

    func groups(for category: CleanCategory) -> [AssetGroup] {
        switch category {
        case .duplicates: return duplicateGroups
        case .similar: return similarGroups
        case .bursts: return burstGroups
        default: return []
        }
    }

    func assets(for category: CleanCategory) -> [PHAsset] {
        switch category {
        case .screenshots: return screenshots
        case .livePhotos: return livePhotos
        case .blurry: return blurry
        case .largeVideos: return largeVideos
        default: return groups(for: category).flatMap { $0.assets }
        }
    }

    func count(for category: CleanCategory) -> Int {
        category.isGrouped ? groups(for: category).reduce(0) { $0 + $1.assets.count - 1 } : assets(for: category).count
    }

    /// Dung lượng có thể giải phóng (với nhóm: trừ ảnh tốt nhất).
    func reclaimable(for category: CleanCategory) -> Int64 {
        if category.isGrouped {
            return groups(for: category).reduce(Int64(0)) { sum, g in
                sum + g.assets.dropFirst().reduce(Int64(0)) { $0 + size(of: $1) }
            }
        }
        if category == .livePhotos {
            // Ước lượng: phần video đi kèm chiếm khoảng một nửa.
            return assets(for: category).reduce(Int64(0)) { $0 + size(of: $1) / 2 }
        }
        return assets(for: category).reduce(Int64(0)) { $0 + size(of: $1) }
    }

    var totalReclaimable: Int64 {
        [CleanCategory.duplicates, .similar, .bursts, .screenshots, .blurry].reduce(Int64(0)) { $0 + reclaimable(for: $1) }
    }

    func size(of asset: PHAsset) -> Int64 { sizes[asset.localIdentifier] ?? 0 }

    func size(of ids: Set<String>) -> Int64 { ids.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) } }

    mutating func remove(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        func filterGroups(_ groups: [AssetGroup]) -> [AssetGroup] {
            groups.compactMap { g in
                let left = g.assets.filter { !ids.contains($0.localIdentifier) }
                return left.count >= 2 ? AssetGroup(left) : nil
            }
        }
        duplicateGroups = filterGroups(duplicateGroups)
        similarGroups = filterGroups(similarGroups)
        burstGroups = filterGroups(burstGroups)
        let keep: (PHAsset) -> Bool = { !ids.contains($0.localIdentifier) }
        screenshots = screenshots.filter(keep)
        livePhotos = livePhotos.filter(keep)
        blurry = blurry.filter(keep)
        largeVideos = largeVideos.filter(keep)
        let removedVideos = allVideos.count
        allVideos = allVideos.filter(keep)
        totalVideos -= removedVideos - allVideos.count
        totalBytes -= size(of: ids)
    }
}

// MARK: - Cài đặt

enum Prefs {
    static let similarThreshold = "similarThreshold"   // 0.2 ... 0.8
    static let blurThreshold = "blurThreshold"         // 10 ... 200
    static let largeVideoMB = "largeVideoMB"
    static let allowICloud = "allowICloud"
    static let freedBytes = "freedBytes"
    static let reviewedMonths = "reviewedMonths"

    static let defaultSimilar = 0.5
    static let defaultBlur = 60.0
    static let defaultLargeVideoMB = 50.0

    static func double(_ key: String, _ def: Double) -> Double {
        (UserDefaults.standard.object(forKey: key) as? Double) ?? def
    }

    static func addFreed(_ bytes: Int64) {
        guard bytes > 0 else { return }
        let cur = UserDefaults.standard.double(forKey: freedBytes)
        UserDefaults.standard.set(cur + Double(bytes), forKey: freedBytes)
    }
}

// MARK: - Tiện ích

extension Int64 {
    var bytesText: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

extension PHAsset {
    var durationText: String {
        let t = Int(duration.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

func formatDate(_ date: Date?) -> String {
    guard let date else { return "" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "vi_VN")
    f.dateStyle = .medium
    f.timeStyle = .short
    return f.string(from: date)
}
