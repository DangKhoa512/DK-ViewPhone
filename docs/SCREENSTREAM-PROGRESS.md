# ĐK ScreenStream — tiến độ 24/10/2026

Yêu cầu hiện tại là hai package độc lập: giữ `com.dk.viewphone` dùng RFB và phát
triển `com.dk.screenstream` dùng JPEG/WebSocket trên cổng 5802. Yêu cầu này thay
thế phương án gộp các module vào ĐK ViewPhone. Chưa kết luận engine nào nhanh hơn.

## Đã xác minh bằng phân tích tĩnh

- DEB FarmBIOS 0.30.2: 1.314.606 byte; SHA-256
  `3806e29eaa879423331d1f011d929eb55e3b7a7a7527bbea4e47610e034f31ed`.
- `control` khai báo `rootless-compat (>=0.9)`. Payload có bản mirror dưới
  `var/mobile/Library/pkgmirror`, mirror có RPATH `/var/jb`, bản hoạt động dùng
  `@loader_path/.jbroot`, cùng các link `.roothidepatch` tới AutoPatches. Đây là
  bằng chứng lớp compatibility/patch, không chứng minh toàn bộ toolchain gốc.
- Năm binary chính là FAT với slice arm64 và arm64e; architecture của package
  không đồng nghĩa binary chỉ chạy trên arm64e. Các crypt_id được đọc là 0.
- Tweak filter liệt kê SpringBoard và nhiều app khác. ScreenStream không sao chép
  filter hoặc hook các app này.
- Chỉ mục Objective-C ARM64 đã khôi phục: capture/JPEG trong `FBCCapture`, lịch
  stream trong `FBCStream`, chuyển tiếp trong `FBCDaemon`, hàng đợi trong
  `FBCFrameServer`. Đã lưu disassembly/call graph có địa chỉ, chưa chạy FarmBIOS.

Bằng chứng máy đọc được nằm trong `artifacts/farmbase-0.30.2/inventory.json`,
`indexes/` và `disassembly/`. Đây là dữ liệu phân tích cục bộ, không đóng gói hoặc
đẩy binary/tài nguyên FarmBIOS vào mã nguồn bàn giao.

## Thiết kế đang triển khai

- Project Theos riêng tại `screenstream/`; executable, daemon, preferences, log,
  tài nguyên web và trạng thái riêng. ĐK ViewPhone không thay engine.
- Capture native, xử lý scale/orientation, ImageIO JPEG, queue giới hạn và ưu tiên
  frame mới. Protocol/version, xác thực, giới hạn client, timeout và cleanup riêng.
- Phiên bản đầu ưu tiên luồng xem; input chỉ bổ sung sau khi xác minh xem ổn định.
  Không cung cấp nút điều khiển giả hoặc coi input chưa triển khai là PASS.
- Preset Low/Balanced/High theo yêu cầu là điểm khởi đầu, không phải cam kết FPS.
- Không tái sử dụng code/binary/key/tài nguyên FarmBIOS. Những API và ý tưởng được
  xác minh sẽ được triển khai độc lập; thành phần GPL/BSD của project hiện tại chỉ
  tái dùng khi có ghi công và giữ giấy phép.

## Trạng thái kiểm thử

ĐK ViewPhone baseline đã có DEB CI ngày 19/10, xem `DEB-BUILD-2026-10-19.md`.
Đó là baseline trước đợt này, không phải kết quả ScreenStream.

ScreenStream: build, cài đặt, FPS/CPU/RAM, vòng connect/disconnect và benchmark
30 phút/1 giờ/2 giờ hiện **NOT TESTED**. Không suy diễn kết quả từ tên hàm hoặc
chuỗi log của FarmBIOS. Báo cáo sẽ cập nhật theo từng bước thực sự hoàn tất.
