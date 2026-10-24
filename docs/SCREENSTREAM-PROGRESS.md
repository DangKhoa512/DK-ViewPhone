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

Baseline ViewPhone đã build lại thành công trong run
[40053842646](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/40053842646),
qua kiểm tra DEB cục bộ và cài trên cùng iPhone với ScreenStream.

ScreenStream commit `23fd4720d17fc15391237d7812427012808e152f` đã build thành công:
[40056808982](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/40056808982).
Linux chạy protocol/queue/WebSocket dưới ASAN/UBSAN và Node viewer tests.
macOS kiểm tra server bằng socket thật, ImageIO JPEG và IOSurface/vImage với
scale + bốn góc xoay, rồi build/kiểm tra native roothide DEB.

Thiết bị: iPhone8,1 (iPhone 6s), iOS 15.8.4, Dopamine roothide, USB SSH ghim
host key. Hai package đã cài cùng lúc, cấu hình ViewPhone được sao lưu trước test.
Bản ScreenStream từ run 40055724326 đã xem hình thật qua Chrome/LAN, 488 × 867,
đúng thứ tự dải màu RGB/white trên fixture độc lập. Không tái sử dụng FarmBIOS.

| Kiểm tra thiết bị | Trạng thái |
|---|---|
| Cài đồng thời com.dk.viewphone + com.dk.screenstream | PASS |
| ScreenStream capture → JPEG → Chrome canvas | PASS |
| Client chưa auth không nhận ảnh; sai mã đóng 1008 | PASS |
| Lệnh input bị từ chối 1008; viewer vượt giới hạn đóng 1013 | PASS |
| 30 vòng kết nối/ngắt, mỗi vòng nhận ảnh | PASS |
| Giữ màn hình fixture sáng bằng assertion tạm thời | PASS; không sửa Auto-Lock |
| RAM khi ngắt trước/sau 30 vòng | 3376 / 3568 KiB RSS, cùng worker; chưa chứng minh không leak dài hạn |
| Scale + rotation trên IOSurface thật, macOS | PASS; xoay vật lý iPhone chưa kiểm tra |
| FPS/CPU/RAM với fixture chuyển động và so sánh baseline | ĐÃ DỪNG theo yêu cầu; chưa có phép đo đối chiếu hoàn chỉnh |
| Mốc 30 phút / 1 giờ / 2 giờ cho cả hai engine | NOT COMPLETED; không công bố PASS |
| Độ trễ hiển thị / tap-to-display | NOT TESTED; ScreenStream chưa có input |
| Farm nhiều iPhone | NOT TESTED; hiện có một iPhone |

Lỗi tìm được và đã sửa: SDK không xuất header IOSurface công khai; C++ modules
không tương thích deployment target iOS 15; worker thiếu quyền hai IOKit user
client của IOSurface khiến capture thất bại. Bổ sung mã lỗi từng bước capture,
exit code/signal và thu metrics cuối trước khi reap worker. Recovery bản cuối
cũng xử lý lỗi liên tiếp xuất hiện sau khi đã capture thành công.

Fixture riêng và probe tại `devkit/stream-benchmark/`. Test dùng assertion giữ
màn hình sáng tạm thời đã được hệ thống chấp nhận; không sửa Auto-Lock. Cấu hình
benchmark chỉ bật một engine. Người dùng yêu cầu tạm bỏ kiểm thử để bàn giao build;
đợt benchmark dài đã dừng, số liệu baseline thu một phần không được dùng để kết
luận engine nào nhanh hơn. RTT là khứ hồi ping,
không được báo như độ trễ hiển thị một chiều.

Phân tích có địa chỉ/bằng chứng: [FarmBIOS pipeline](FARMBIOS-SCREEN-PIPELINE.md).
Đối chiếu baseline: [hai engine](DUAL-ENGINE-BASELINE.md). Không suy diễn hiệu năng
từ tên hàm, log hoặc việc build thành công.
