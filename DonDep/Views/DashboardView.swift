import SwiftUI
import Photos

enum Route: Hashable {
    case category(CleanCategory)
    case swipe
    case compress
    case contacts
    case calendar
    case vault
    case settings
}

struct DashboardView: View {
    @EnvironmentObject var scanner: ScanEngine
    @AppStorage(Prefs.freedBytes) private var freedBytes: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if scanner.authStatus == .limited { LimitedBanner() }
                    StorageCard()
                    ScanCard()
                    sectionHeader("Ảnh & video")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(CleanCategory.allCases) { c in
                            NavigationLink(value: Route.category(c)) {
                                CategoryCard(category: c)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    sectionHeader("Công cụ")
                    VStack(spacing: 0) {
                        ToolRow(route: .swipe, icon: "hand.draw", color: .teal, title: "Vuốt để dọn", subtitle: "Duyệt nhanh ảnh theo từng tháng")
                        Divider().padding(.leading, 60)
                        ToolRow(route: .compress, icon: "arrow.down.right.and.arrow.up.left", color: .green, title: "Nén video", subtitle: "Giảm dung lượng, giữ chất lượng")
                        Divider().padding(.leading, 60)
                        ToolRow(route: .contacts, icon: "person.2.fill", color: .blue, title: "Danh bạ trùng lặp", subtitle: "Gộp liên hệ trùng tên, trùng số")
                        Divider().padding(.leading, 60)
                        ToolRow(route: .calendar, icon: "calendar", color: .red, title: "Sự kiện lịch cũ", subtitle: "Xóa sự kiện đã qua lâu")
                        Divider().padding(.leading, 60)
                        ToolRow(route: .vault, icon: "lock.rectangle.stack.fill", color: .indigo, title: "Kho ảnh bí mật", subtitle: "Cất ảnh riêng tư, khóa Face ID")
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    if freedBytes > 0 {
                        Label("Tổng đã giải phóng: \(Int64(freedBytes).bytesText)", systemImage: "leaf.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dọn Dẹp")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.settings) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .category(let c):
                    if c.isGrouped { GroupReviewView(category: c) } else { AssetGridView(category: c) }
                case .swipe: SwipeMonthListView()
                case .compress: VideoCompressView()
                case .contacts: ContactsView()
                case .calendar: CalendarCleanView()
                case .vault: VaultView()
                case .settings: SettingsView()
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }
}

// MARK: - Thẻ dung lượng

struct StorageCard: View {
    @EnvironmentObject var scanner: ScanEngine
    @State private var total: Int64 = 0
    @State private var free: Int64 = 0

    var used: Int64 { max(0, total - free) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color(.systemFill), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(AngularGradient(colors: [.indigo, .purple, .pink], center: .center),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(fraction * 100))%").font(.title2.bold())
                    Text("đã dùng").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 8) {
                Text("Bộ nhớ iPhone").font(.headline)
                Text("\(used.bytesText) / \(total.bytesText)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("Còn trống \(free.bytesText)", systemImage: "internaldrive")
                    .font(.footnote)
                if let r = scanner.result {
                    Label("Ảnh & video: \(r.totalBytes.bytesText)", systemImage: "photo.on.rectangle")
                        .font(.footnote)
                    Text("\(r.totalPhotos) ảnh · \(r.totalVideos) video")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .onAppear(perform: refresh)
        .onChange(of: scanner.result?.date) { _, _ in refresh() }
    }

    func refresh() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            total = Int64(v.volumeTotalCapacity ?? 0)
            free = v.volumeAvailableCapacityForImportantUsage ?? 0
        }
    }
}

// MARK: - Thẻ quét

struct ScanCard: View {
    @EnvironmentObject var scanner: ScanEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if scanner.isScanning {
                HStack {
                    Text("Đang quét…").font(.headline)
                    Spacer()
                    Button("Dừng") { scanner.cancelScan() }
                        .font(.subheadline)
                }
                ProgressView(value: scanner.progress)
                Text(scanner.status).font(.caption).foregroundStyle(.secondary)
            } else if let r = scanner.result {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Có thể giải phóng").font(.subheadline).foregroundStyle(.secondary)
                        Text(r.totalReclaimable.bytesText)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.indigo.gradient)
                    }
                    Spacer()
                    Button {
                        scanner.startScan()
                    } label: {
                        Label("Quét lại", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                Text("Quét lúc \(formatDate(r.date))" + (r.skippedCloud > 0 ? " · \(r.skippedCloud) ảnh chỉ có trên iCloud chưa được phân tích" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button {
                    scanner.startScan()
                } label: {
                    Label("Bắt đầu quét", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Thẻ danh mục

struct CategoryCard: View {
    @EnvironmentObject var scanner: ScanEngine
    let category: CleanCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: category.icon)
                .font(.title2)
                .foregroundStyle(category.color)
                .frame(width: 44, height: 44)
                .background(category.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            Text(category.title)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let r = scanner.result {
                let n = r.count(for: category)
                Text(n == 0 ? "Sạch sẽ ✓" : "\(n) mục · \(r.reclaimable(for: category).bytesText)")
                    .font(.caption)
                    .foregroundStyle(n == 0 ? .green : .secondary)
            } else {
                Text(scanner.isScanning ? "Đang quét…" : "Chưa quét")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ToolRow: View {
    let route: Route
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LimitedBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Chỉ truy cập một phần ảnh").font(.subheadline.bold())
                Text("Ứng dụng chỉ quét được những ảnh bạn đã chọn. Hãy cho phép \"Truy cập toàn bộ\" để dọn dẹp hiệu quả.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Mở Cài đặt") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.caption.bold())
            }
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}
