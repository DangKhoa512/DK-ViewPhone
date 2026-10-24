# Hai DEB native roothide — 24/10/2026

Đã build hai package độc lập; không build EXE. Theo yêu cầu mới nhất, tạm dừng
benchmark dài hạn và tập trung bàn giao DEB. Không kết luận engine nào nhanh hơn.

| File | Package / phiên bản | SHA-256 |
|---|---|---|
| DKViewPhone_roothide.deb | com.dk.viewphone / 1.3.0 | `79a7d6643e5fb75698e8302f9654de03b5bf3e5e2de8ebc9c78ca1b9c29f11d1` |
| DKScreenStream_roothide.deb | com.dk.screenstream / 0.1.0 | `cc7eec733efd810f914c2ea8f1ee9fbe815d6ddd9113f955c272b22ed6cf052a` |

ViewPhone: [workflow thành công, artifact DKViewPhone_1.3.0_roothide](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/40053842646),
commit `ec6779efaf474229c7adf509a26d3b5d7869d195`.
ScreenStream: [workflow thành công, artifact DKScreenStream_0.1.0_roothide](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/40056808982),
commit `23fd4720d17fc15391237d7812427012808e152f`.
Mỗi artifact có DEB, source archive và SHA256SUMS; GitHub có thể yêu cầu đăng nhập
để tải và artifact có thời hạn lưu. Bản sao cục bộ ở `artifacts/dual-engine-20261024/`.

Build dùng macOS 15/Xcode 16.2, roothide/Theos được ghim commit, SDK 16.5,
deployment target iOS 15.0, Mach-O ARM64 và architecture package iphoneos-arm64e.
Kiểm tra metadata/dependency, Mach-O/signature/entitlement, daemon, scripts,
preferences, web assets và SHA-256 đều đạt trên CI và sau khi tải về Windows.
ScreenStream không có dependency rootless-compat hoặc payload FarmBIOS.

Đã cài cùng lúc trên iPhone 6s/iOS 15.8.4 qua USB SSH ghim host key. Luồng
ScreenStream đã nhận JPEG thật trong Chrome, đúng dải màu fixture, kiểm tra auth,
giới hạn viewer và 30 vòng kết nối/ngắt đạt. Đã thử gỡ ScreenStream khi ViewPhone
đang xem: kết nối và cấu hình ViewPhone không đổi, preferences ScreenStream vẫn
được giữ; sau đó cài lại bản cuối. Đây là kiểm tra chức năng cơ bản, không thay
thế benchmark 30 phút/1 giờ/2 giờ, đo nhiều iPhone hoặc kiểm thử input mới.

## Cài và bật/tắt

Cài từng DEB bằng trình quản lý gói roothide hoặc `dpkg -i <file.deb>` trên iPhone.
Không cài bản dành cho rootful/rootless tiêu chuẩn thay cho roothide.

- **ViewPhone:** dùng Settings → ĐK ViewPhone và công tắc hiện có. RFB 5901,
  web 5801; giữ các tính năng VNC/input/clipboard/recovery/Multi View hiện có.
  Khi nâng cấp giữ các cấu hình đã lưu, kể cả bind IP thủ công.
- **ScreenStream:** Settings → ĐK ScreenStream → Sao chép mã kết nối → bật.
  Mở `http://<IPv4 iPhone>:5802/` trên PC cùng LAN và nhập mã. Mặc định tắt,
  `BindHost=auto`; chọn IPv4 LAN hiện có, không hardcode địa chỉ của máy test.
  Chỉ xem; chưa có tap/swipe/keyboard. Mã chỉ giữ trong RAM của viewer.
- Hai công tắc, daemon, executable, preference domain, log và cổng riêng.
  Khi so sánh hiệu năng chỉ bật một engine. HTTP/WS chưa có TLS; dùng LAN tin cậy
  hoặc tunnel SSH. Không mở cổng ra Internet.

## Những phần còn lại

Benchmark đối chiếu dài hạn, farm nhiều iPhone, độ trễ hiển thị và tap-to-display
chưa hoàn tất. Xoay vật lý iPhone chưa kiểm thử; test IOSurface/vImage trên macOS
đã kiểm tra bốn góc xoay. Input ScreenStream sẽ là giai đoạn tiếp theo sau khi
luồng xem được xác minh đủ ổn định, không cung cấp nút điều khiển giả.

Multi-Device Viewer hiện dùng RFB. Có thể thêm adapter `screenstream` với cùng
vòng đời connect/disconnect, một socket cho mỗi máy và JPEG decoder bounded;
phải giữ URL/token/protocol và quyền input riêng theo engine. Chưa tuyên bố
ScreenStream đã được tích hợp vào desktop Multi View.

Xem [pipeline FarmBIOS có bằng chứng](FARMBIOS-SCREEN-PIPELINE.md),
[đối chiếu hai engine](DUAL-ENGINE-BASELINE.md),
[source và hướng dẫn ScreenStream](../screenstream/README.md),
[protocol DKSS/1](../screenstream/PROTOCOL.md) và
[tiến độ kiểm thử thực](SCREENSTREAM-PROGRESS.md).
