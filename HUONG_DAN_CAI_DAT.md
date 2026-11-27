# Dọn Dẹp: hướng dẫn cài lên iPhone (từ Windows)

## Chuẩn bị (làm 1 lần)

1. **Cài iTunes bản tải từ web Apple** (không dùng bản Microsoft Store):
   https://www.apple.com/itunes/download/win64
2. **Cài Sideloadly**: https://sideloadly.io (bản Windows)
3. Cắm iPhone vào máy tính bằng cáp, mở khóa iPhone, bấm **"Tin cậy"** máy tính này.

## Tải file app

- Vào repo GitHub › mục **Releases** › bản **latest** › tải `DonDep.ipa`.
- Mỗi lần code được đẩy lên, GitHub Actions tự build lại file này (mất khoảng 5–10 phút).

## Cài đặt

1. Mở Sideloadly, kéo file `DonDep.ipa` vào cửa sổ.
2. Ô **Apple ID**: nhập Apple ID của bạn (nên dùng một Apple ID phụ nếu muốn).
3. Bấm **Start**, nhập mật khẩu Apple ID khi Sideloadly hỏi. Mật khẩu chỉ gửi tới Apple.
4. Trên iPhone:
   - **Cài đặt › Quyền riêng tư & Bảo mật › Chế độ nhà phát triển** › Bật › Khởi động lại máy.
   - **Cài đặt › Cài đặt chung › Quản lý VPN & Thiết bị** › chọn Apple ID của bạn › **Tin cậy**.
5. Mở app **Dọn Dẹp**, chọn **"Cho phép truy cập toàn bộ"** ảnh.

## Gia hạn 7 ngày (Apple ID miễn phí)

App ký bằng Apple ID miễn phí sẽ hết hạn sau 7 ngày. Có hai cách gia hạn:

- **Tự động:** trong Sideloadly bật **Automatic refresh** sau lần cài đầu tiên. Máy tính bật Sideloadly và iPhone cùng mạng Wi-Fi thì app tự được gia hạn.
- **Thủ công:** cắm cáp và bấm Start lại với cùng file IPA. **Dữ liệu trong app (kể cả Kho bí mật) vẫn được giữ nguyên.**

## Lưu ý khi dùng

- Mỗi lần xóa, iOS sẽ hiện hộp thoại xác nhận. Đây là cơ chế bảo vệ của Apple, không app nào bỏ qua được.
- Ảnh đã xóa nằm trong **Ảnh › Album › Đã xóa gần đây** 30 ngày. Muốn lấy lại dung lượng ngay thì vào đó và chọn **Xóa tất cả**.
- Lần quét đầu với thư viện lớn (20.000+ ảnh) mất vài phút. Nên cắm sạc và để app mở trong lúc quét. Các lần quét sau rất nhanh nhờ bộ nhớ đệm.
- Ảnh chỉ nằm trên iCloud (chưa tải về máy) sẽ bị bỏ qua, trừ khi bạn bật "Tải ảnh iCloud để phân tích" trong Cài đặt.

## Tính năng

| Mục | Mô tả |
|---|---|
| Ảnh trùng lặp | So sánh dấu vân tay ảnh 256-bit, tìm cả ảnh gửi qua Zalo/Messenger bị nén lại |
| Ảnh tương tự | AI Vision của Apple so sánh các ảnh chụp gần nhau, tự chọn ảnh nét nhất để giữ |
| Ảnh chụp liên tiếp | Giữ ảnh bạn đã chọn hoặc ảnh iOS gợi ý, xóa các khung còn lại |
| Ảnh chụp màn hình | Lọc toàn bộ |
| Ảnh Live | Chuyển sang ảnh tĩnh (giữ ngày, vị trí, yêu thích), tiết kiệm khoảng 50% |
| Ảnh mờ & tối | Đo độ nét bằng thuật toán Laplacian, chỉnh được độ nhạy |
| Video lớn | Sắp xếp theo dung lượng |
| Nén video | HEVC 1080p / giữ độ phân giải / 720p |
| Vuốt để dọn | Duyệt ảnh từng tháng: vuốt trái để xóa, vuốt phải để giữ |
| Danh bạ | Gộp liên hệ trùng tên, trùng số; xóa liên hệ trống |
| Lịch | Xóa sự kiện cũ |
| Kho bí mật | Cất ảnh riêng tư, khóa bằng Face ID |

## Cấu trúc mã nguồn

- `project.yml`: cấu hình dự án (XcodeGen tạo file `.xcodeproj` khi build)
- `.github/workflows/build.yml`: build IPA trên máy Mac của GitHub
- `DonDep/Core`: thuật toán quét, xóa, chuyển Live, nén video, danh bạ, lịch, kho bí mật
- `DonDep/Views`: giao diện SwiftUI
