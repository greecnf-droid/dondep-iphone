import SwiftUI
import Photos

/// Lưới ảnh cho các danh mục đơn: chụp màn hình, Live, mờ & tối, video lớn.
struct AssetGridView: View {
    let category: CleanCategory
    @EnvironmentObject var scanner: ScanEngine
    @State private var selected: Set<String> = []
    @State private var sort: SortMode = .default
    @State private var preview: IdentifiedAsset?
    @State private var working = false
    @State private var workingText = ""
    @State private var alert: AlertMessage?
    @State private var confirmDelete = false
    @State private var confirmConvert = false

    enum SortMode: String, CaseIterable, Identifiable {
        case `default`, newest, oldest, largest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .default: return "Mặc định"
            case .newest: return "Mới nhất"
            case .oldest: return "Cũ nhất"
            case .largest: return "Dung lượng lớn nhất"
            }
        }
    }

    var assets: [PHAsset] {
        let base = scanner.result?.assets(for: category) ?? []
        switch sort {
        case .default: return base
        case .newest: return base.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .oldest: return base.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        case .largest: return base.sorted { (scanner.result?.size(of: $0) ?? 0) > (scanner.result?.size(of: $1) ?? 0) }
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        let list = assets
        Group {
            if list.isEmpty {
                EmptyStateView(icon: "checkmark.seal.fill", title: "Không có gì để dọn",
                               message: "Không tìm thấy \(category.title.lowercased()).")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(hint).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(list, id: \.localIdentifier) { asset in
                                let id = asset.localIdentifier
                                SelectableThumb(asset: asset, selected: selected.contains(id),
                                                sizeText: showSize ? scanner.result?.size(of: asset).bytesText : nil)
                                    .onTapGesture { toggle(id) }
                                    .onLongPressGesture { preview = IdentifiedAsset(asset: asset) }
                            }
                        }
                        .padding(.horizontal, 3)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(selected.count == list.count ? "Bỏ chọn tất cả" : "Chọn tất cả (\(list.count))") {
                        if selected.count == list.count { selected.removeAll() }
                        else { selected = Set(list.map { $0.localIdentifier }) }
                    }
                    Picker("Sắp xếp", selection: $sort) {
                        ForEach(SortMode.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !list.isEmpty {
                BottomActionBar(title: "Xóa \(selected.count) mục · \(scanner.size(of: selected).bytesText)",
                                enabled: !selected.isEmpty, working: working, action: { confirmDelete = true }) {
                    if category == .livePhotos {
                        Button {
                            confirmConvert = true
                        } label: {
                            Label("Chuyển \(selected.count) ảnh sang ảnh tĩnh", systemImage: "livephoto.slash")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selected.isEmpty || working)
                    }
                }
            }
        }
        .overlay {
            if working && !workingText.isEmpty { ProgressOverlay(text: workingText) }
        }
        .confirmationDialog("Xóa \(selected.count) mục đã chọn?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xóa", role: .destructive) { Task { await deleteSelected() } }
        } message: {
            Text("Mục đã xóa nằm trong \"Đã xóa gần đây\" 30 ngày.")
        }
        .confirmationDialog("Chuyển \(selected.count) ảnh Live sang ảnh tĩnh?", isPresented: $confirmConvert, titleVisibility: .visible) {
            Button("Chuyển đổi") { Task { await convertSelected() } }
        } message: {
            Text("Ứng dụng tạo ảnh tĩnh mới (giữ ngày chụp, vị trí, yêu thích) và xóa bản Live cũ. Ảnh mới sẽ không còn nằm trong album cũ.")
        }
        .sheet(item: $preview) { p in
            AssetPreviewSheet(asset: p.asset, sizeText: scanner.result?.size(of: p.asset).bytesText)
        }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.text), dismissButton: .default(Text("OK")))
        }
    }

    private var showSize: Bool { category == .largeVideos || sort == .largest }

    private var hint: String {
        switch category {
        case .blurry: return "Sắp xếp từ mờ nhất. Có thể chỉnh độ nhạy trong Cài đặt. Nhấn giữ để xem lớn."
        case .livePhotos: return "Chuyển sang ảnh tĩnh để bỏ phần video 3 giây đi kèm, tiết kiệm khoảng một nửa dung lượng."
        case .largeVideos: return "Mẹo: dùng công cụ \"Nén video\" ở màn hình chính nếu muốn giữ video nhưng giảm dung lượng."
        default: return "Chạm để chọn, nhấn giữ để xem lớn."
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func deleteSelected() async {
        let toDelete = assets.filter { selected.contains($0.localIdentifier) }
        working = true
        let outcome = await scanner.delete(toDelete)
        working = false
        switch outcome {
        case .success(let msg):
            selected.removeAll()
            alert = AlertMessage(title: "Hoàn tất", text: msg)
        case .failed(let msg):
            alert = AlertMessage(title: "Lỗi", text: msg)
        case .cancelled: break
        }
    }

    private func convertSelected() async {
        let list = assets.filter { selected.contains($0.localIdentifier) }
        let sizes = scanner.result?.sizes ?? [:]
        working = true
        workingText = "Đang chuẩn bị…"
        do {
            let res = try await PhotoActions.convertLiveToStill(list, sizes: sizes) { i, n in
                Task { @MainActor in workingText = "Đang xuất ảnh \(i)/\(n)…" }
            }
            scanner.removeFromResult(res.removedIDs)
            selected.subtract(res.removedIDs)
            Prefs.addFreed(res.savedBytes)
            alert = AlertMessage(title: "Hoàn tất",
                                 text: "Đã chuyển \(res.converted) ảnh, tiết kiệm khoảng \(res.savedBytes.bytesText)." +
                                 (res.failed > 0 ? "\n\(res.failed) ảnh không xử lý được." : ""))
        } catch {
            alert = AlertMessage(title: "Lỗi", text: error.localizedDescription)
        }
        working = false
        workingText = ""
    }
}
