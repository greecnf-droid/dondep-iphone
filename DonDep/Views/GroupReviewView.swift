import SwiftUI
import Photos

/// Duyệt các nhóm ảnh (trùng lặp / tương tự / burst). Ảnh đầu nhóm là ảnh tốt nhất được giữ lại.
struct GroupReviewView: View {
    let category: CleanCategory
    @EnvironmentObject var scanner: ScanEngine
    @State private var selected: Set<String> = []
    @State private var initialized = false
    @State private var preview: IdentifiedAsset?
    @State private var working = false
    @State private var alert: AlertMessage?
    @State private var confirm = false

    var groups: [AssetGroup] { scanner.result?.groups(for: category) ?? [] }

    var body: some View {
        Group {
            if groups.isEmpty {
                EmptyStateView(icon: "checkmark.seal.fill", title: "Không có gì để dọn",
                               message: "Không tìm thấy \(category.title.lowercased()).")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        Text("Ảnh có nhãn \"Tốt nhất\" sẽ được giữ lại. Chạm vào ảnh để chọn/bỏ chọn, nhấn giữ để xem lớn.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                            groupSection(idx, group)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Chọn theo gợi ý", systemImage: "wand.and.stars") { selectSuggested() }
                    Button("Bỏ chọn tất cả", systemImage: "circle") { selected.removeAll() }
                } label: {
                    Image(systemName: "checklist")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !groups.isEmpty {
                BottomActionBar(title: "Xóa \(selected.count) ảnh · \(scanner.size(of: selected).bytesText)",
                                enabled: !selected.isEmpty, working: working) { confirm = true }
            }
        }
        .confirmationDialog("Xóa \(selected.count) ảnh đã chọn?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Xóa \(selected.count) ảnh", role: .destructive) { Task { await deleteSelected() } }
        } message: {
            Text("Ảnh sẽ được chuyển vào \"Đã xóa gần đây\" và có thể khôi phục trong 30 ngày.")
        }
        .sheet(item: $preview) { p in
            AssetPreviewSheet(asset: p.asset, sizeText: scanner.result?.size(of: p.asset).bytesText)
        }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.text), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            if !initialized { selectSuggested(); initialized = true }
        }
    }

    @ViewBuilder
    private func groupSection(_ idx: Int, _ group: AssetGroup) -> some View {
        let groupSize = group.assets.reduce(Int64(0)) { $0 + (scanner.result?.size(of: $1) ?? 0) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nhóm \(idx + 1)").font(.headline)
                Text("\(group.assets.count) ảnh · \(groupSize.bytesText)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(formatDate(group.assets.first?.creationDate))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(group.assets.enumerated()), id: \.element.localIdentifier) { i, asset in
                        let id = asset.localIdentifier
                        SelectableThumb(asset: asset, selected: selected.contains(id), side: 130,
                                        isBest: i == 0, sizeText: scanner.result?.size(of: asset).bytesText)
                            .frame(width: 130, height: 130)
                            .onTapGesture { toggle(id) }
                            .onLongPressGesture { preview = IdentifiedAsset(asset: asset) }
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func selectSuggested() {
        var s = Set<String>()
        for g in groups { for a in g.assets.dropFirst() { s.insert(a.localIdentifier) } }
        selected = s
    }

    private func deleteSelected() async {
        let assets = groups.flatMap { $0.assets }.filter { selected.contains($0.localIdentifier) }
        working = true
        let outcome = await scanner.delete(assets)
        working = false
        switch outcome {
        case .success(let msg):
            selected.removeAll()
            alert = AlertMessage(title: "Hoàn tất", text: msg)
        case .failed(let msg):
            alert = AlertMessage(title: "Lỗi", text: msg)
        case .cancelled:
            break
        }
    }
}
