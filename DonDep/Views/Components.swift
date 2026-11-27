import SwiftUI
import Photos
import AVKit

// MARK: - Tải ảnh thu nhỏ

final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 600 }

    func load(_ asset: PHAsset, side: CGFloat, fit: Bool = false) async -> UIImage? {
        let key = "\(asset.localIdentifier)-\(Int(side))-\(fit)" as NSString
        if let img = cache.object(forKey: key) { return img }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        let target = CGSize(width: side * 2.5, height: side * 2.5)
        let manager = self.manager
        let image: UIImage? = await withCheckedContinuation { c in
            let once = ResumeOnce()
            manager.requestImage(for: asset, targetSize: target,
                                 contentMode: fit ? .aspectFit : .aspectFill,
                                 options: opts) { img, _ in
                if once.claim() { c.resume(returning: img) }
            }
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

final class ResumeOnce {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: - Ô ảnh

struct AssetThumbnail: View {
    let asset: PHAsset
    var side: CGFloat = 120
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    Label(asset.durationText, systemImage: "play.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                } else if asset.mediaSubtypes.contains(.photoLive) {
                    Image(systemName: "livephoto")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                image = await ThumbnailLoader.shared.load(asset, side: side)
            }
    }
}

struct SelectableThumb: View {
    let asset: PHAsset
    let selected: Bool
    var side: CGFloat = 120
    var isBest = false
    var sizeText: String?

    var body: some View {
        AssetThumbnail(asset: asset, side: side)
            .overlay {
                if selected {
                    Color.black.opacity(0.25)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, selected ? Color.red : Color.black.opacity(0.35))
                    .font(.title3)
                    .padding(5)
            }
            .overlay(alignment: .topLeading) {
                if isBest {
                    Text("Tốt nhất")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.green, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let sizeText {
                    Text(sizeText)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Xem ảnh lớn

struct AssetLargeImage: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task(id: asset.localIdentifier) {
            image = await ThumbnailLoader.shared.load(asset, side: 500, fit: true)
        }
    }
}

struct AssetPreviewSheet: View {
    let asset: PHAsset
    var sizeText: String?
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if asset.mediaType == .video {
                    if let player {
                        VideoPlayer(player: player)
                    } else {
                        ProgressView().tint(.white)
                    }
                } else {
                    AssetLargeImage(asset: asset)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    VStack {
                        Text(formatDate(asset.creationDate)).font(.footnote)
                        Text("\(asset.pixelWidth)×\(asset.pixelHeight)" + (sizeText.map { " · \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .toolbarBackground(.visible, for: .bottomBar)
        }
        .task {
            guard asset.mediaType == .video else { return }
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            let item: AVPlayerItem? = await withCheckedContinuation { c in
                PHImageManager.default().requestPlayerItem(forVideo: asset, options: opts) { item, _ in
                    c.resume(returning: item)
                }
            }
            if let item {
                player = AVPlayer(playerItem: item)
                player?.play()
            }
        }
    }
}

// MARK: - Thanh hành động dưới cùng

struct BottomActionBar<Extra: View>: View {
    let title: String
    let enabled: Bool
    let working: Bool
    let action: () -> Void
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(spacing: 8) {
            extra()
            Button(role: .destructive, action: action) {
                HStack {
                    if working { ProgressView().tint(.white) }
                    Text(title).font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!enabled || working)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}

extension BottomActionBar where Extra == EmptyView {
    init(title: String, enabled: Bool, working: Bool, action: @escaping () -> Void) {
        self.init(title: title, enabled: enabled, working: working, action: action, extra: { EmptyView() })
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(.green.gradient)
            Text(title).font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProgressOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(text).font(.subheadline).multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(40)
        }
    }
}

/// Thông báo đơn giản dùng chung.
struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}
