import Foundation
import LocalAuthentication
import Photos
import PhotosUI
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct VaultItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
}

/// Kho ảnh bí mật: ảnh được sao chép vào vùng riêng của ứng dụng, khóa bằng Face ID.
@MainActor
final class VaultStore: ObservableObject {
    @Published var unlocked = false
    @Published var items: [VaultItem] = []
    @Published var authError: String?

    var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func unlock() async {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // Máy không đặt mật mã: vẫn cho mở.
            unlocked = true
            reload()
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Mở Kho ảnh bí mật")
            unlocked = ok
            if ok { reload() }
        } catch {
            authError = error.localizedDescription
        }
    }

    func lock() {
        unlocked = false
        items = []
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        items = urls.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }.map { VaultItem(url: $0) }
    }

    /// Nhập ảnh, trả về localIdentifier của ảnh gốc (để có thể xóa khỏi Thư viện).
    func importItems(_ picks: [PhotosPickerItem]) async -> [String] {
        var ids: [String] = []
        for item in picks {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let url = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                if let id = item.itemIdentifier { ids.append(id) }
            } catch { continue }
        }
        reload()
        return ids
    }

    func delete(_ item: VaultItem) {
        try? FileManager.default.removeItem(at: item.url)
        reload()
    }

    func exportToLibrary(_ item: VaultItem) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, fileURL: item.url, options: nil)
        }
    }

    nonisolated static func thumbnail(_ url: URL, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
