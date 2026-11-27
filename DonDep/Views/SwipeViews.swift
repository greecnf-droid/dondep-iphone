import SwiftUI
import Photos

struct MonthBucket: Identifiable, Hashable {
    let id: String          // yyyy-MM
    let title: String
    let assets: [PHAsset]

    static func == (a: MonthBucket, b: MonthBucket) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Chọn tháng để vuốt dọn.
struct SwipeMonthListView: View {
    @State private var months: [MonthBucket] = []
    @State private var loading = true
    @AppStorage(Prefs.reviewedMonths) private var reviewedRaw = ""

    var reviewed: Set<String> { Set(reviewedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        List {
            Section {
                Text("Vuốt trái để xóa, vuốt phải để giữ. Ảnh chỉ bị xóa khi bạn xác nhận ở cuối.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Theo tháng") {
                ForEach(months) { m in
                    NavigationLink {
                        SwipeDeckView(month: m)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(m.title).font(.body)
                                Text("\(m.assets.count) ảnh").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if reviewed.contains(m.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
        .overlay { if loading { ProgressView() } }
        .navigationTitle("Vuốt để dọn")
        .task {
            guard months.isEmpty else { return }
            months = await Task.detached(priority: .userInitiated) { SwipeMonthListView.buildMonths() }.value
            loading = false
        }
    }

    nonisolated static func buildMonths() -> [MonthBucket] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let r = PHAsset.fetchAssets(with: opts)
        let cal = Calendar.current
        var order: [String] = []
        var dict: [String: [PHAsset]] = [:]
        r.enumerateObjects { a, _, _ in
            guard let d = a.creationDate else { return }
            let c = cal.dateComponents([.year, .month], from: d)
            let key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(a)
        }
        return order.map { key in
            let parts = key.split(separator: "-")
            let title = "Tháng \(Int(parts[1]) ?? 0), \(parts[0])"
            return MonthBucket(id: key, title: title, assets: dict[key] ?? [])
        }
    }
}

/// Bộ bài vuốt kiểu "giữ / xóa".
struct SwipeDeckView: View {
    let month: MonthBucket
    @EnvironmentObject var scanner: ScanEngine
    @AppStorage(Prefs.reviewedMonths) private var reviewedRaw = ""
    @State private var index = 0
    @State private var toDelete: [PHAsset] = []
    @State private var history: [Bool] = []   // true = xóa
    @State private var offset: CGSize = .zero
    @State private var finished = false
    @State private var working = false
    @State private var alert: AlertMessage?

    var body: some View {
        VStack(spacing: 16) {
            if finished || index >= month.assets.count {
                summary
            } else {
                HStack {
                    Text("\(index + 1)/\(month.assets.count)").font(.headline.monospacedDigit())
                    Spacer()
                    Label("\(toDelete.count)", systemImage: "trash").foregroundStyle(.red)
                }
                .padding(.horizontal)

                ZStack {
                    if index + 1 < month.assets.count {
                        card(month.assets[index + 1])
                            .scaleEffect(0.95)
                            .opacity(0.6)
                    }
                    card(month.assets[index])
                        .offset(offset)
                        .rotationEffect(.degrees(Double(offset.width / 25)))
                        .overlay(alignment: .top) { stamp }
                        .gesture(
                            DragGesture()
                                .onChanged { offset = $0.translation }
                                .onEnded { v in
                                    if v.translation.width < -110 { decide(delete: true) }
                                    else if v.translation.width > 110 { decide(delete: false) }
                                    else { withAnimation(.spring) { offset = .zero } }
                                }
                        )
                }
                .padding(.horizontal)

                HStack(spacing: 36) {
                    circleButton("trash.fill", .red) { decide(delete: true) }
                    circleButton("arrow.uturn.backward", .gray) { undo() }
                        .disabled(history.isEmpty)
                    circleButton("heart.fill", .green) { decide(delete: false) }
                }
                .padding(.bottom)
            }
        }
        .navigationTitle(month.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !finished {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { finished = true }
                }
            }
        }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.text), dismissButton: .default(Text("OK")))
        }
    }

    private func card(_ asset: PHAsset) -> some View {
        AssetLargeImage(asset: asset)
            .frame(maxWidth: .infinity)
            .frame(height: 460)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .overlay(alignment: .bottomLeading) {
                Text(formatDate(asset.creationDate))
                    .font(.caption.bold())
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
    }

    @ViewBuilder private var stamp: some View {
        if offset.width < -40 {
            Text("XÓA").font(.largeTitle.weight(.black)).foregroundStyle(.red)
                .padding(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(.red, lineWidth: 4))
                .rotationEffect(.degrees(12)).padding(30)
                .opacity(min(1, Double(-offset.width) / 110))
        } else if offset.width > 40 {
            Text("GIỮ").font(.largeTitle.weight(.black)).foregroundStyle(.green)
                .padding(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(.green, lineWidth: 4))
                .rotationEffect(.degrees(-12)).padding(30)
                .opacity(min(1, Double(offset.width) / 110))
        }
    }

    private func circleButton(_ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(color)
                .frame(width: 64, height: 64)
                .background(Color(.secondarySystemBackground), in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
    }

    private func decide(delete: Bool) {
        guard index < month.assets.count else { return }
        let asset = month.assets[index]
        withAnimation(.easeOut(duration: 0.2)) {
            offset = CGSize(width: delete ? -600 : 600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if delete { toDelete.append(asset) }
            history.append(delete)
            index += 1
            offset = .zero
        }
    }

    private func undo() {
        guard let last = history.popLast(), index > 0 else { return }
        index -= 1
        if last { _ = toDelete.popLast() }
    }

    private var summary: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("Đã duyệt \(index) ảnh").font(.title2.bold())
            Text("\(toDelete.count) ảnh được đánh dấu xóa · \(scanner.size(of: Set(toDelete.map { $0.localIdentifier })).bytesText)")
                .foregroundStyle(.secondary)
            if !toDelete.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(toDelete, id: \.localIdentifier) { a in
                            AssetThumbnail(asset: a, side: 70).frame(width: 70, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }.padding(.horizontal)
                }
                Button(role: .destructive) {
                    Task { await commitDelete() }
                } label: {
                    HStack {
                        if working { ProgressView().tint(.white) }
                        Text("Xóa \(toDelete.count) ảnh").font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .padding(.horizontal)
                .disabled(working)
            }
            if finished && index < month.assets.count {
                Button("Tiếp tục duyệt") { finished = false }
            }
            Spacer()
        }
        .onAppear {
            if index >= month.assets.count { markReviewed() }
        }
    }

    private func markReviewed() {
        var set = Set(reviewedRaw.split(separator: ",").map(String.init))
        set.insert(month.id)
        reviewedRaw = set.sorted().joined(separator: ",")
    }

    private func commitDelete() async {
        working = true
        let outcome = await scanner.delete(toDelete)
        working = false
        switch outcome {
        case .success(let msg):
            toDelete.removeAll()
            history = history.map { _ in false }
            alert = AlertMessage(title: "Hoàn tất", text: msg)
        case .failed(let msg):
            alert = AlertMessage(title: "Lỗi", text: msg)
        case .cancelled: break
        }
    }
}
