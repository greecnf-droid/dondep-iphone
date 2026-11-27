import Foundation
import Photos
import SwiftUI

@MainActor
final class ScanEngine: ObservableObject {
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var status = ""
    @Published var result: ScanResult?
    @Published var authStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private var token: CancelToken?

    func requestAccess() async {
        authStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func refreshAuth() {
        authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        progress = 0
        status = "Chuẩn bị…"
        let params = ScanParams(
            similarThreshold: Float(Prefs.double(Prefs.similarThreshold, Prefs.defaultSimilar)),
            blurThreshold: Float(Prefs.double(Prefs.blurThreshold, Prefs.defaultBlur)),
            largeVideoBytes: Int64(Prefs.double(Prefs.largeVideoMB, Prefs.defaultLargeVideoMB) * 1_000_000),
            allowNetwork: UserDefaults.standard.bool(forKey: Prefs.allowICloud))
        let token = CancelToken()
        self.token = token

        Task.detached(priority: .userInitiated) { [weak self] in
            let res = ScanWorker.run(params: params, token: token) { p, s in
                Task { @MainActor [weak self] in
                    guard let self, self.isScanning else { return }
                    self.progress = p
                    self.status = s
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let res { self.result = res }
                self.isScanning = false
                self.token = nil
            }
        }
    }

    func cancelScan() {
        token?.cancel()
    }

    /// Cập nhật kết quả sau khi ảnh bị xóa/thay thế.
    func removeFromResult(_ ids: Set<String>) {
        result?.remove(ids)
    }

    func size(of ids: Set<String>) -> Int64 {
        result?.size(of: ids) ?? 0
    }

    // MARK: Xóa

    enum Outcome {
        case success(String)
        case cancelled
        case failed(String)
    }

    func delete(_ assets: [PHAsset]) async -> Outcome {
        guard !assets.isEmpty else { return .cancelled }
        let ids = Set(assets.map { $0.localIdentifier })
        let bytes = size(of: ids)
        do {
            try await PhotoActions.delete(assets)
            removeFromResult(ids)
            Prefs.addFreed(bytes)
            return .success("Đã xóa \(assets.count) mục, giải phóng \(bytes.bytesText).\nẢnh nằm trong album \"Đã xóa gần đây\" 30 ngày – hãy vào đó xóa vĩnh viễn để lấy lại dung lượng ngay.")
        } catch {
            if PhotoActions.isUserCancel(error) { return .cancelled }
            return .failed(error.localizedDescription)
        }
    }
}
