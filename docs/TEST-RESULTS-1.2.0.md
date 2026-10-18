# ĐK ViewPhone 1.2.0 — kết quả thực tế

Build [GitHub Actions 39111854823](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39111854823) đạt trên commit `51d9065`. [Artifact DEB/source](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39111854823/artifacts/12130647292) chứa `DKViewPhone_1.2.0_roothide.deb`, SHA-256 `d1b84c7da312c7a8f0e8c430a987355651b21bcc1d1bff19cf5c1a1839eb245c`.

Validator độc lập xác nhận package `com.dk.viewphone`, kiến trúc gói `iphoneos-arm64e`, 206 payload entries và bốn Mach-O arm64 đã ký. Tweak thay đồng hồ bằng IPv4 không còn nằm trong DEB.

Trên iPhone 6s iOS 15.8.4 Dopamine roothide, nâng cấp 1.1.4 → 1.2.0 và respring thành công. Chỉ còn một watchdog và một VNC server lắng nghe 5801/5901; không có crash report mới. Chrome trên Windows tải Multi View từ chính iPhone, kết nối và hiển thị canvas không có lỗi trang.

Frontend mới đã được thử với một endpoint LAN hoạt động cùng một endpoint lỗi; lỗi của một card không làm rớt card online. Bài giới hạn yêu cầu tám card tới cùng một iPhone và chỉ sáu phiên được mở, hai phiên còn lại chờ. Mật khẩu không được ghi vào browser storage.

Chưa có đủ nhiều iPhone để xác nhận 2/4/8/12 thiết bị vật lý. Chưa đo CPU/RAM theo từng iPhone, băng thông tổng, FPS thực tế, độ trễ glass-to-glass hoặc memory leak dài hạn. Máy thử được nâng cấp nên cấu hình đã lưu được giữ nguyên; các mặc định cài mới đã được xác minh trong source và payload, chưa được kiểm chứng bằng thao tác xóa sạch preferences trên thiết bị thật.
