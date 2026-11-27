import Foundation
import Photos
import AVFoundation

enum PhotoActions {

    // MARK: Xóa

    static func delete(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    static func isUserCancel(_ error: Error) -> Bool {
        if let pe = error as? PHPhotosError, pe.code == .userCancelled { return true }
        let ns = error as NSError
        return ns.code == 3072 || (ns.domain == PHPhotosErrorDomain && ns.code == PHPhotosError.Code.userCancelled.rawValue)
    }

    // MARK: Ảnh Live -> ảnh tĩnh

    struct ConvertResult {
        var converted = 0
        var failed = 0
        var savedBytes: Int64 = 0
        var removedIDs = Set<String>()
    }

    /// Xuất ảnh tĩnh từ Live Photo, tạo ảnh mới (giữ ngày chụp, vị trí, yêu thích) rồi xóa bản Live.
    /// Mỗi lô 60 ảnh = 1 lần xác nhận của iOS.
    static func convertLiveToStill(_ assets: [PHAsset], sizes: [String: Int64],
                                   progress: @escaping (Int, Int) -> Void) async throws -> ConvertResult {
        var result = ConvertResult()
        let batchSize = 60
        var index = 0
        let total = assets.count
        while index < total {
            let batch = Array(assets[index..<min(total, index + batchSize)])
            var prepared: [(URL, PHAsset, Int64)] = []
            for asset in batch {
                index += 1
                progress(index, total)
                let resources = PHAssetResource.assetResources(for: asset)
                guard let res = resources.first(where: { $0.type == .fullSizePhoto })
                        ?? resources.first(where: { $0.type == .photo }) else {
                    result.failed += 1
                    continue
                }
                var ext = (res.originalFilename as NSString).pathExtension
                if ext.isEmpty { ext = "heic" }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                do {
                    try await writeResource(res, to: url)
                    let newSize = fileSize(url)
                    let old = sizes[asset.localIdentifier] ?? ImageAnalysis.fileSize(of: asset)
                    prepared.append((url, asset, max(0, old - newSize)))
                } catch {
                    result.failed += 1
                }
            }
            guard !prepared.isEmpty else { continue }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for (url, asset, _) in prepared {
                        let req = PHAssetCreationRequest.forAsset()
                        let o = PHAssetResourceCreationOptions()
                        o.shouldMoveFile = true
                        req.addResource(with: .photo, fileURL: url, options: o)
                        req.creationDate = asset.creationDate
                        req.location = asset.location
                        req.isFavorite = asset.isFavorite
                    }
                    PHAssetChangeRequest.deleteAssets(prepared.map { $0.1 } as NSArray)
                }
                result.converted += prepared.count
                result.savedBytes += prepared.reduce(Int64(0)) { $0 + $1.2 }
                prepared.forEach { result.removedIDs.insert($0.1.localIdentifier) }
            } catch {
                prepared.forEach { try? FileManager.default.removeItem(at: $0.0) }
                if isUserCancel(error) { return result }
                throw error
            }
        }
        return result
    }

    static func writeResource(_ res: PHAssetResource, to url: URL) async throws {
        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: res, toFile: url, options: opts) { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }

    static func fileSize(_ url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(v?.fileSize ?? 0)
    }

    // MARK: Nén video

    enum CompressPreset: String, CaseIterable, Identifiable {
        case hevc1080, hevcHigh, h264720
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hevc1080: return "1080p HEVC"
            case .hevcHigh: return "Giữ độ phân giải"
            case .h264720: return "720p"
            }
        }
        var detail: String {
            switch self {
            case .hevc1080: return "Cân bằng tốt nhất. Video 4K giảm 60–80%."
            case .hevcHigh: return "Giữ nguyên độ phân giải, chỉ nén lại bằng HEVC."
            case .h264720: return "Nhỏ nhất, phù hợp video ít quan trọng."
            }
        }
        var avPreset: String {
            switch self {
            case .hevc1080: return AVAssetExportPresetHEVC1920x1080
            case .hevcHigh: return AVAssetExportPresetHEVCHighestQuality
            case .h264720: return AVAssetExportPreset1280x720
            }
        }
    }

    struct CompressResult {
        var compressed = 0
        var skipped = 0
        var savedBytes: Int64 = 0
        var removedIDs = Set<String>()
    }

    static func requestAVAsset(_ asset: PHAsset) async -> AVAsset? {
        let opts = PHVideoRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        opts.version = .current
        return await withCheckedContinuation { c in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { av, _, _ in
                c.resume(returning: av)
            }
        }
    }

    /// Nén lần lượt, sau đó thay thế toàn bộ bằng 1 lần xác nhận.
    static func compressVideos(_ assets: [PHAsset], preset: CompressPreset, sizes: [String: Int64],
                               progress: @escaping (Int, Int) -> Void) async throws -> CompressResult {
        var result = CompressResult()
        var prepared: [(URL, PHAsset, Int64)] = []
        for (i, asset) in assets.enumerated() {
            progress(i + 1, assets.count)
            let original = sizes[asset.localIdentifier] ?? ImageAnalysis.fileSize(of: asset)
            guard let av = await requestAVAsset(asset),
                  let session = AVAssetExportSession(asset: av, presetName: preset.avPreset) else {
                result.skipped += 1
                continue
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            session.outputURL = url
            session.outputFileType = .mov
            session.shouldOptimizeForNetworkUse = false
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { c.resume() }
            }
            let newSize = fileSize(url)
            if session.status == .completed, newSize > 0, Double(newSize) < Double(original) * 0.9 {
                prepared.append((url, asset, original - newSize))
            } else {
                try? FileManager.default.removeItem(at: url)
                result.skipped += 1
            }
        }
        guard !prepared.isEmpty else { return result }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for (url, asset, _) in prepared {
                    let req = PHAssetCreationRequest.forAsset()
                    let o = PHAssetResourceCreationOptions()
                    o.shouldMoveFile = true
                    req.addResource(with: .video, fileURL: url, options: o)
                    req.creationDate = asset.creationDate
                    req.location = asset.location
                    req.isFavorite = asset.isFavorite
                }
                PHAssetChangeRequest.deleteAssets(prepared.map { $0.1 } as NSArray)
            }
            result.compressed = prepared.count
            result.savedBytes = prepared.reduce(Int64(0)) { $0 + $1.2 }
            prepared.forEach { result.removedIDs.insert($0.1.localIdentifier) }
        } catch {
            prepared.forEach { try? FileManager.default.removeItem(at: $0.0) }
            if !isUserCancel(error) { throw error }
        }
        return result
    }
}
