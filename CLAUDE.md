# Dọn Dẹp: ghi chú cho Claude

App iOS cá nhân (SwiftUI, iOS 17+) để dọn ảnh trên iPhone 13 / iOS 18.6: ảnh trùng, tương tự, burst, chụp màn hình, Live → ảnh tĩnh, mờ/tối, video lớn, nén video, vuốt dọn theo tháng, danh bạ trùng, lịch cũ, kho bí mật Face ID. Giao diện tiếng Việt; trả lời người dùng bằng tiếng Việt.

## Build & cài

- Người dùng dùng Windows, không có Mac. Không build được ở máy local.
- GitHub Actions (`.github/workflows/build.yml`, runner macos-15) dùng XcodeGen (`project.yml`) để build IPA không ký, rồi đăng lên release tag `latest` của repo `greecnf-droid/dondep-iphone` (repo công khai).
- Sửa code → push lên `main` → xem kết quả bằng `gh run list` / `gh run view <id> --log-failed`.
- Cài lên iPhone bằng Sideloadly với Apple ID miễn phí (hết hạn sau 7 ngày). Hướng dẫn đầy đủ trong `HUONG_DAN_CAI_DAT.md`.
- Claude không nhập Apple ID/mật khẩu thay người dùng; các bước trên iPhone (Tin cậy, Chế độ nhà phát triển) do người dùng tự làm.

## Cấu trúc

- `DonDep/Core`: ScanWorker (thuật toán quét, cache), ImageAnalysis (dHash 256-bit, Laplacian, Vision feature print), PhotoActions (xóa, Live → tĩnh, nén video), ContactsCleaner, CalendarCleaner, VaultStore.
- `DonDep/Views`: Dashboard, GroupReview, AssetGrid, Swipe, ToolViews (nén video, danh bạ, lịch, kho, cài đặt).
- Swift language mode 5 (`SWIFT_VERSION 5.0`) để tránh lỗi strict concurrency.

## Trạng thái (27/11/2026)

- Build #1 thành công, IPA khoảng 611 KB. Chưa cài và chạy thử trên iPhone thật.
- Việc tiếp theo: hỗ trợ cài bằng Sideloadly, rồi chỉnh thuật toán theo phản hồi thực tế (ngưỡng ảnh tương tự mặc định 0.5, ngưỡng mờ 60).
