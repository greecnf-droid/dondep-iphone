import SwiftUI
import Photos
import Contacts
import EventKit
import PhotosUI

// MARK: - Nén video

struct VideoCompressView: View {
    @EnvironmentObject var scanner: ScanEngine
    @State private var selected: Set<String> = []
    @State private var preset: PhotoActions.CompressPreset = .hevc1080
    @State private var working = false
    @State private var workingText = ""
    @State private var alert: AlertMessage?

    var videos: [PHAsset] { scanner.result?.allVideos ?? [] }

    var body: some View {
        List {
            Section {
                Picker("Chất lượng", selection: $preset) {
                    ForEach(PhotoActions.CompressPreset.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(preset.detail).font(.footnote).foregroundStyle(.secondary)
            } footer: {
                Text("Video mới giữ nguyên ngày quay, vị trí. Video nào nén không giảm được ít nhất 10% sẽ được giữ nguyên. Nên cắm sạc khi nén nhiều video.")
            }
            Section("Video (\(videos.count)) – lớn nhất trước") {
                if videos.isEmpty {
                    Text(scanner.result == nil ? "Hãy quét thư viện trước." : "Không có video.")
                        .foregroundStyle(.secondary)
                }
                ForEach(videos, id: \.localIdentifier) { v in
                    let id = v.localIdentifier
                    HStack(spacing: 12) {
                        AssetThumbnail(asset: v, side: 60)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scanner.result?.size(of: v).bytesText ?? "").font(.headline)
                            Text("\(v.pixelWidth)×\(v.pixelHeight) · \(v.durationText)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(formatDate(v.creationDate)).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(selected.contains(id) ? Color.accentColor : Color.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                    }
                }
            }
        }
        .navigationTitle("Nén video")
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await run() }
            } label: {
                Text("Nén \(selected.count) video · \(scanner.size(of: selected).bytesText)")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty || working)
            .padding()
            .background(.bar)
        }
        .overlay { if working { ProgressOverlay(text: workingText) } }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.text), dismissButton: .default(Text("OK")))
        }
    }

    private func run() async {
        let list = videos.filter { selected.contains($0.localIdentifier) }
        working = true
        workingText = "Đang chuẩn bị…"
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            working = false
        }
        do {
            let res = try await PhotoActions.compressVideos(list, preset: preset, sizes: scanner.result?.sizes ?? [:]) { i, n in
                Task { @MainActor in workingText = "Đang nén video \(i)/\(n)…\nGiữ ứng dụng mở trong lúc nén." }
            }
            scanner.removeFromResult(res.removedIDs)
            selected.subtract(res.removedIDs)
            Prefs.addFreed(res.savedBytes)
            var text = "Đã nén \(res.compressed) video, tiết kiệm \(res.savedBytes.bytesText)."
            if res.skipped > 0 { text += "\n\(res.skipped) video không giảm được đáng kể nên giữ nguyên." }
            if res.compressed > 0 { text += "\nQuét lại để thấy video mới trong danh sách." }
            alert = AlertMessage(title: "Hoàn tất", text: text)
        } catch {
            alert = AlertMessage(title: "Lỗi", text: error.localizedDescription)
        }
    }
}

// MARK: - Danh bạ

struct ContactsView: View {
    @StateObject private var cleaner = ContactsCleaner()
    @State private var alert: AlertMessage?
    @State private var confirmAll = false
    @State private var confirmEmpty = false
    @State private var working = false

    var body: some View {
        Group {
            switch cleaner.state {
            case .idle, .loading:
                ProgressView("Đang đọc danh bạ…")
            case .denied:
                EmptyStateView(icon: "person.crop.circle.badge.xmark", title: "Chưa có quyền Danh bạ",
                               message: "Vào Cài đặt › Dọn Dẹp › Danh bạ để cho phép.")
            case .loaded:
                if cleaner.groups.isEmpty && cleaner.emptyContacts.isEmpty {
                    EmptyStateView(icon: "checkmark.seal.fill", title: "Danh bạ sạch sẽ",
                                   message: "Không có liên hệ trùng trong \(cleaner.total) liên hệ.")
                } else {
                    list
                }
            }
        }
        .navigationTitle("Danh bạ")
        .task { if cleaner.state == .idle { await cleaner.load() } }
        .overlay { if working { ProgressOverlay(text: "Đang xử lý…") } }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.text), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog("Gộp tất cả \(cleaner.groups.count) nhóm?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Gộp tất cả", role: .destructive) {
                perform { try await cleaner.mergeAll() }
            }
        } message: {
            Text("Mỗi nhóm giữ lại liên hệ đầy đủ nhất và bổ sung số điện thoại/email từ các bản trùng. Không thể hoàn tác.")
        }
        .confirmationDialog("Xóa \(cleaner.emptyContacts.count) liên hệ trống?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Xóa", role: .destructive) {
                perform { try await cleaner.deleteEmpty() }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                Text("Tổng \(cleaner.total) liên hệ · \(cleaner.groups.count) nhóm trùng")
                    .font(.footnote).foregroundStyle(.secondary)
                if !cleaner.groups.isEmpty {
                    Button("Gộp tất cả \(cleaner.groups.count) nhóm") { confirmAll = true }
                }
                if !cleaner.emptyContacts.isEmpty {
                    Button("Xóa \(cleaner.emptyContacts.count) liên hệ trống", role: .destructive) { confirmEmpty = true }
                }
            }
            ForEach(cleaner.groups) { g in
                Section {
                    ForEach(Array(g.contacts.enumerated()), id: \.element.identifier) { i, c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(ContactsCleaner.displayName(c)).font(.body.bold())
                                if i == 0 {
                                    Text("Giữ lại").font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.green.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }
                            ForEach(c.phoneNumbers, id: \.identifier) { p in
                                Text(p.value.stringValue).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(c.emailAddresses, id: \.identifier) { e in
                                Text(e.value as String).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Gộp nhóm này") {
                        perform { try await cleaner.merge(g) }
                    }
                } header: {
                    Text(g.reason)
                }
            }
        }
    }

    private func perform(_ op: @escaping () async throws -> Void) {
        Task {
            working = true
            do {
                try await op()
            } catch {
                alert = AlertMessage(title: "Lỗi", text: error.localizedDescription)
            }
            working = false
        }
    }
}

// MARK: - Lịch

struct CalendarCleanView: View {
    @StateObject private var cleaner = CalendarCleaner()
    @State private var monthsOld = 12
    @State private var selected: Set<String> = []
    @State private var alert: AlertMessage?
    @State private var confirm = false

    var body: some View {
        List {
            Section {
                Picker("Sự kiện cũ hơn", selection: $monthsOld) {
                    Text("3 tháng").tag(3)
                    Text("6 tháng").tag(6)
                    Text("1 năm").tag(12)
                    Text("2 năm").tag(24)
                }
            } footer: {
                Text("Không bao gồm sự kiện lặp lại và lịch chỉ đọc (ngày lễ, sinh nhật).")
            }
            switch cleaner.state {
            case .idle, .loading:
                HStack { Spacer(); ProgressView(); Spacer() }
            case .denied:
                Text("Chưa có quyền truy cập Lịch. Vào Cài đặt › Dọn Dẹp › Lịch để cho phép.")
                    .foregroundStyle(.secondary)
            case .loaded:
                Section {
                    if cleaner.events.isEmpty {
                        Text("Không có sự kiện cũ.").foregroundStyle(.secondary)
                    } else {
                        Button(selected.count == cleaner.events.count ? "Bỏ chọn tất cả" : "Chọn tất cả (\(cleaner.events.count))") {
                            if selected.count == cleaner.events.count { selected.removeAll() }
                            else { selected = Set(cleaner.events.compactMap { $0.eventIdentifier }) }
                        }
                    }
                    ForEach(cleaner.events, id: \.eventIdentifier) { e in
                        let id = e.eventIdentifier ?? ""
                        HStack {
                            Circle().fill(Color(cgColor: e.calendar.cgColor)).frame(width: 10, height: 10)
                            VStack(alignment: .leading) {
                                Text(e.title ?? "(Không tiêu đề)")
                                Text(formatDate(e.startDate)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(id) ? Color.red : Color.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                        }
                    }
                } header: {
                    Text("\(cleaner.events.count) sự kiện")
                }
            }
        }
        .navigationTitle("Lịch cũ")
        .task(id: monthsOld) {
            selected.removeAll()
            await cleaner.load(monthsOld: monthsOld)
        }
        .safeAreaInset(edge: .bottom) {
            if !cleaner.events.isEmpty {
                BottomActionBar(title: "Xóa \(selected.count) sự kiện", enabled: !selected.isEmpty, working: false) {
                    confirm = true
                }
            }
        }
        .confirmationDialog("Xóa \(selected.count) sự kiện?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Xóa", role: .destructive) {
                do {
                    let n = try cleaner.delete(selected)
                    selected.removeAll()
                    alert = AlertMessage(title: "Hoàn tất", text: "Đã xóa \(n) sự kiện.")
                } catch {
                    alert = AlertMessage(title: "Lỗi", text: error.localizedDescription)
                }
            }
        } message: {
            Text("Không thể hoàn tác.")
        }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.text), dismissButton: .default(Text("OK")))
        }
    }
}

// MARK: - Kho bí mật

struct VaultView: View {
    @StateObject private var vault = VaultStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var picks: [PhotosPickerItem] = []
    @State private var importedIDs: [String] = []
    @State private var askDeleteOriginals = false
    @State private var viewing: VaultItem?
    @State private var alert: AlertMessage?
    @State private var importing = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        Group {
            if vault.unlocked {
                ScrollView {
                    if vault.items.isEmpty {
                        EmptyStateView(icon: "lock.rectangle.stack", title: "Kho trống",
                                       message: "Nhấn + để cất ảnh vào kho. Ảnh trong kho chỉ xem được sau khi xác thực Face ID.")
                    }
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(vault.items) { item in
                            VaultThumb(item: item)
                                .onTapGesture { viewing = item }
                        }
                    }
                    .padding(3)
                    Text("Lưu ý: xóa ứng dụng sẽ xóa luôn ảnh trong kho. Khi cài lại bản mới bằng Sideloadly (cùng Apple ID), dữ liệu được giữ nguyên.")
                        .font(.caption2).foregroundStyle(.secondary).padding()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        PhotosPicker(selection: $picks, matching: .images, photoLibrary: .shared()) {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { vault.lock() } label: { Image(systemName: "lock.fill") }
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 70)).foregroundStyle(.indigo.gradient)
                    Text("Kho ảnh bí mật").font(.title2.bold())
                    Button {
                        Task { await vault.unlock() }
                    } label: {
                        Label("Mở khóa bằng Face ID", systemImage: "faceid").padding(.horizontal).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    if let e = vault.authError { Text(e).font(.caption).foregroundStyle(.red) }
                }
                .task { await vault.unlock() }
            }
        }
        .navigationTitle("Kho bí mật")
        .overlay { if importing { ProgressOverlay(text: "Đang cất ảnh vào kho…") } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { vault.lock() }
        }
        .onChange(of: picks) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task {
                importing = true
                importedIDs = await vault.importItems(newValue)
                importing = false
                picks = []
                if !importedIDs.isEmpty { askDeleteOriginals = true }
            }
        }
        .confirmationDialog("Xóa \(importedIDs.count) ảnh gốc khỏi Thư viện ảnh?", isPresented: $askDeleteOriginals, titleVisibility: .visible) {
            Button("Xóa ảnh gốc", role: .destructive) {
                Task {
                    let r = PHAsset.fetchAssets(withLocalIdentifiers: importedIDs, options: nil)
                    var list: [PHAsset] = []
                    r.enumerateObjects { a, _, _ in list.append(a) }
                    try? await PhotoActions.delete(list)
                    importedIDs = []
                }
            }
            Button("Giữ ảnh gốc", role: .cancel) { importedIDs = [] }
        } message: {
            Text("Ảnh đã được sao chép vào kho. Xóa bản gốc để ảnh không còn hiện trong ứng dụng Ảnh.")
        }
        .fullScreenCover(item: $viewing) { item in
            VaultDetailView(item: item, vault: vault) { msg in alert = msg }
        }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.text), dismissButton: .default(Text("OK")))
        }
    }
}

struct VaultThumb: View {
    let item: VaultItem
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .aspectRatio(1, contentMode: .fit)
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .clipped()
            .contentShape(Rectangle())
            .task(id: item.url) {
                let url = item.url
                image = await Task.detached { VaultStore.thumbnail(url, maxPixel: 300) }.value
            }
    }
}

struct VaultDetailView: View {
    let item: VaultItem
    @ObservedObject var vault: VaultStore
    let onMessage: (AlertMessage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView().tint(.white) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Đóng") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    ShareLink(item: item.url) { Image(systemName: "square.and.arrow.up") }
                    Spacer()
                    Button {
                        Task {
                            do {
                                try await vault.exportToLibrary(item)
                                onMessage(AlertMessage(title: "Đã lưu", text: "Ảnh đã được lưu lại vào Thư viện ảnh."))
                            } catch {
                                onMessage(AlertMessage(title: "Lỗi", text: error.localizedDescription))
                            }
                        }
                    } label: { Label("Đưa ra Thư viện", systemImage: "photo.badge.plus") }
                    Spacer()
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                }
            }
            .toolbarBackground(.visible, for: .bottomBar)
            .confirmationDialog("Xóa vĩnh viễn ảnh này khỏi kho?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Xóa vĩnh viễn", role: .destructive) {
                    vault.delete(item)
                    dismiss()
                }
            }
        }
        .task {
            let url = item.url
            image = await Task.detached { VaultStore.thumbnail(url, maxPixel: 2400) }.value
        }
    }
}

// MARK: - Cài đặt

struct SettingsView: View {
    @EnvironmentObject var scanner: ScanEngine
    @AppStorage(Prefs.similarThreshold) private var similar = Prefs.defaultSimilar
    @AppStorage(Prefs.blurThreshold) private var blur = Prefs.defaultBlur
    @AppStorage(Prefs.largeVideoMB) private var largeVideoMB = Prefs.defaultLargeVideoMB
    @AppStorage(Prefs.allowICloud) private var allowICloud = false
    @AppStorage(Prefs.freedBytes) private var freedBytes: Double = 0
    @State private var cacheSize = ScanCache.sizeOnDisk

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text("Độ nhạy ảnh tương tự: \(similarLabel)")
                    Slider(value: $similar, in: 0.25...0.8, step: 0.05)
                    Text("Cao hơn = gom được nhiều ảnh hơn nhưng dễ gom nhầm.").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text("Ngưỡng ảnh mờ: \(Int(blur))")
                    Slider(value: $blur, in: 10...200, step: 5)
                    Text("Cao hơn = nhiều ảnh bị coi là mờ hơn.").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text("Video lớn từ: \(Int(largeVideoMB)) MB")
                    Slider(value: $largeVideoMB, in: 10...500, step: 10)
                }
                Toggle("Tải ảnh iCloud để phân tích", isOn: $allowICloud)
            } header: {
                Text("Quét")
            } footer: {
                Text("Sau khi thay đổi, nhấn \"Quét lại\" ở màn hình chính. Lần quét sau rất nhanh nhờ bộ nhớ đệm. Bật tải iCloud sẽ tốn dữ liệu mạng.")
            }

            Section("Dữ liệu") {
                LabeledContent("Đã giải phóng", value: Int64(freedBytes).bytesText)
                LabeledContent("Bộ nhớ đệm quét", value: cacheSize.bytesText)
                Button("Xóa bộ nhớ đệm") {
                    ScanCache.clear()
                    cacheSize = 0
                }
                Button("Quét lại ngay") { scanner.startScan() }
                    .disabled(scanner.isScanning)
            }

            Section {
                Button("Mở album \"Đã xóa gần đây\"") {
                    if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
                }
            } footer: {
                Text("iOS giữ ảnh đã xóa 30 ngày. Để lấy lại dung lượng ngay: mở Ảnh › Album › Đã xóa gần đây › Chọn › Xóa tất cả.")
            }

            Section("Giới thiệu") {
                LabeledContent("Phiên bản", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                Text("Mọi phân tích chạy trên máy, không gửi dữ liệu ra ngoài. Ứng dụng cài bằng Apple ID miễn phí cần gia hạn mỗi 7 ngày qua Sideloadly.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cài đặt")
    }

    private var similarLabel: String {
        switch similar {
        case ..<0.4: return "Thấp"
        case ..<0.6: return "Vừa"
        default: return "Cao"
        }
    }
}
