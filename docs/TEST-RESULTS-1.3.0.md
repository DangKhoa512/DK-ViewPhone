# ĐK ViewPhone 1.3.0 — kết quả dashboard một trang

Build [GitHub Actions 39113475065](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39113475065) đạt trên commit `dc84b8a`. [Artifact DEB/source](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39113475065/artifacts/12131342527) chứa `DKViewPhone_1.3.0_roothide.deb`, SHA-256 `91b2866266ad93a17841a0153cc5e3f02f78b2b5f7ac15eb3271508c4edd97f7`.

Validator độc lập xác nhận package `com.dk.viewphone` phiên bản 1.3.0, kiến trúc package roothide `iphoneos-arm64e`, 206 payload entries và bốn Mach-O arm64 có chữ ký ad-hoc hợp lệ. HTML, CSS, JS nguồn, bundle noVNC và cấu hình mặc định nằm trong DEB.

Source tests đạt 11/11. Bài Node đạt xác thực None/password, xóa credential, reconnect 2/4/8/16/16 giây, LAN/USB endpoint và cấu hình quality riêng cho preview/focus. Chrome với dữ liệu mẫu đạt giao diện một trang, lưới năm cột, click chọn, mở/đóng focus, đổi máy không reload, tìm kiếm và không lưu mật khẩu.

Một RFB/WebSocket server giả lập đã chạy hai preview cùng lúc. Mở Focus Panel khi giới hạn live bằng hai làm preview của máy focus nhường slot; preview máy còn lại giữ online. Đổi focus sang máy thứ hai không reload và không làm rớt preview còn lại.

DEB được nâng cấp thực tế từ 1.2.0 lên 1.3.0 trên iPhone 6s, iOS 15.8.4, Dopamine roothide. Một watchdog và một server chạy, listener thiết bị báo `192.168.1.158:5801` và `:5901`, không có crash report mới. Chrome tải trang từ DEB qua SSH USB tunnel, preview và Focus Panel đều online với hai canvas noVNC đồng thời.

Kết nối TCP LAN trực tiếp từ Windows `192.168.1.157` tới iPhone chưa đạt: ping và ARP hoạt động nhưng TCP 5801/5901 không mở được từ PC, trong khi cùng listener hoạt động qua tunnel trên thiết bị. Vì vậy kiểm thử Chrome LAN trực tiếp chưa được đánh dấu PASS. Chưa có nhiều iPhone vật lý để xác nhận việc vận hành đồng thời trên 2/4/8/12 máy, chưa đo FPS/latency thực tế hoặc tải dài hạn.
