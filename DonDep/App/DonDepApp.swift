import SwiftUI
import Photos

@main
struct DonDepApp: App {
    @StateObject private var scanner = ScanEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(scanner)
                .tint(.indigo)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var scanner: ScanEngine
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch scanner.authStatus {
            case .authorized, .limited:
                DashboardView()
                    .task {
                        if scanner.result == nil && !scanner.isScanning { scanner.startScan() }
                    }
            case .notDetermined:
                PermissionView()
            default:
                DeniedView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { scanner.refreshAuth() }
        }
    }
}

struct PermissionView: View {
    @EnvironmentObject var scanner: ScanEngine

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 80))
                .foregroundStyle(.indigo.gradient)
            Text("Dọn Dẹp iPhone")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "square.on.square", text: "Tìm ảnh trùng lặp & tương tự bằng AI")
                FeatureRow(icon: "livephoto", text: "Chuyển ảnh Live sang ảnh tĩnh")
                FeatureRow(icon: "film", text: "Nén video dung lượng lớn")
                FeatureRow(icon: "lock.shield", text: "100% xử lý trên máy, không gửi ảnh đi đâu")
            }
            .padding()
            Spacer()
            Button {
                Task { await scanner.requestAccess() }
            } label: {
                Text("Cho phép truy cập ảnh")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            Text("Hãy chọn \"Cho phép truy cập toàn bộ\" để quét được cả thư viện.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 32)
            Text(text)
        }
    }
}

struct DeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text("Chưa có quyền truy cập ảnh")
                .font(.title2.bold())
            Text("Vào Cài đặt › Quyền riêng tư & Bảo mật › Ảnh › Dọn Dẹp và chọn \"Truy cập toàn bộ\".")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Mở Cài đặt") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
