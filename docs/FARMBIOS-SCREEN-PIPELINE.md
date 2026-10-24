# FarmBIOS 0.30.2: bằng chứng pipeline màn hình

Phân tích tĩnh ngày 24/10/2026, chỉ đọc DEB người dùng cung cấp. Không cài hoặc
chạy binary/script FarmBIOS. Không trích code, tài nguyên, khóa hoặc module cấp
phép vào ScreenStream. Các địa chỉ dưới đây là VM address trước ASLR của **slice
ARM64**, không phải file offset hoặc địa chỉ ARM64e. Một tên hàm/chuỗi riêng lẻ
không đủ chứng minh hành vi; kết luận dựa trên load, branch và call liên quan.

DEB: `com.farmbase.iosctl_0.30.2_iphoneos-arm64e.deb`, 1.314.606 byte, SHA-256
`3806e29eaa879423331d1f011d929eb55e3b7a7a7527bbea4e47610e034f31ed`.
Inventory, Objective-C method map và disassembly được lưu cục bộ tại
`artifacts/farmbase-0.30.2/`; binary gốc không đưa lên GitHub hoặc vào DEB mới.
Tool inventory có source tại `devkit/inspect-deb-static.py`.

## Packaging và ranh giới nghiên cứu

**CONFIRMED:** package khai báo `rootless-compat (>=0.9)`. Có mirror dưới
`var/mobile/Library/pkgmirror`; mirror giữ RPATH `/var/jb`, bản hoạt động dùng
`@loader_path/.jbroot`. Có năm link `.roothidepatch` tới AutoPatches. Đây là bằng
chứng lớp compatibility/patch, không xác định được toolchain nguồn ban đầu.
Năm Mach-O chính có cả slice ARM64 và ARM64e; các trường encryption `crypt_id`
đọc được đều bằng 0. Architecture package không chứng minh chỉ hỗ trợ ARM64e.

`FBCAgent`, `IosCtlTweak.dylib`, `iosctld`, `krclear`, `krproxy` là các thành phần
khác nhau. Tweak có filter nhiều app; ScreenStream không sử dụng filter đó.
Không port module app-data/keychain/TCC/proxy/license: ngoài phạm vi hai engine.
Maintainer scripts chỉ được đọc; không thực thi lệnh trong chúng.

## Capture → compare → JPEG → schedule

| Thành phần | Bằng chứng ARM64 | Kết luận |
|---|---|---|
| Resolve render API | Tweak `0xd020`: tên `CARenderServerRenderDisplay`, gọi `dlsym` tại `0xd034`, lưu pointer ở `0x4ac98`; block invoke được tham chiếu từ `0x404d8` | **CONFIRMED:** resolve API render động. |
| Capture | `+[FBCCapture captureFrameOfSize:completion:]` tại `0xccc8`; gọi render pointer ở `0xcda4`, quản lý IOSurface/dimension cache | **CONFIRMED:** capture dùng IOSurface; thay surface khi kích thước đổi. |
| Pixel ownership | Cùng đường capture: lock IOSurface, copy từng hàng vào NSData, unlock | **CONFIRMED:** có copy pixel; không phải pipeline zero-copy toàn phần. |
| Pixel compare | Callback `0x1167c`, đọc previous pixels ở `0x116f4`, gọi `isEqualToData:` tại `0x11708`, nhánh bỏ qua đi trước encode | **CONFIRMED:** so sánh dữ liệu trước JPEG để bỏ frame giống nhau. Không chứng minh mọi capture đều được bỏ sớm ở GPU. |
| Resize | Encoder `0xc580`, đoạn `0xc650–0xc708`: max(width,height), tính tỷ lệ cạnh, làm tròn và vẽ CGContext | **CONFIRMED:** giữ tỷ lệ ảnh theo maxDimension, không tự kéo giãn hai chiều độc lập. |
| JPEG | `CGImageDestinationCreateWithData` ở `0xc770` với `public.jpeg`, quality ở `0xc7a0`, AddImage/Finalize `0xc7f4/0xc7fc` | **CONFIRMED:** ImageIO JPEG và tham số chất lượng. |
| Cấu hình | Block `0x11228`: FPS clamp 1–60; quality 1–100; maxDimension=0 là nhánh riêng, khác 0 có minimum 64; double tại `0x2a6b0` là 4294967295 | **CONFIRMED:** giới hạn của đường này. Không suy ra đây là default hoặc preset thực tế. |
| Nhịp frame | `scheduleNextAfterStartMs:` tại `0x119c4`; hằng 1000 tại `0x2a608`, chia FPS ở `0x11a04`, trừ elapsed rồi dispatch_after/dispatch_async | **CONFIRMED:** bù thời gian đã xử lý vào khoảng 1000/FPS ms, tránh cộng thêm nguyên chu kỳ sau mỗi capture. |
| Đồng hồ | Helper `0x113e4`: mach_absolute_time, timebase, chia 1.000.000 (double tại `0x2a650`) | **CONFIRMED:** thời gian đơn điệu tính ms trong đường này. Không phải timestamp Unix. |
| Giải phóng | Đường encode: CFRelease destination `0xc80c`, CGImageRelease `0xc818`; capture thay/release surface cũ | **CONFIRMED:** có cleanup ở các đường đã đọc. **UNKNOWN:** không thể chứng minh không leak dài hạn bằng vài đường code. |

`FBCStream` còn có `stop` ở `0x1144c`, `tick` ở `0x11588` và
`reportMetricsIfDue` ở `0x11b34`. Có đường báo thống kê; giá trị log và hiệu năng
runtime chưa được đo. Không coi tên method là bằng chứng FPS thực tế.

## Daemon và backpressure

**CONFIRMED:** `-[FBCDaemon forwardStreamFrame...]` bắt đầu `0x10000ec74`.
Trong `-[FBCFrameServer queueVideoFrameForConnection:payload:]` (`0x10003ec84`),
state block `0x10003ee60` kiểm tra pendingFrame, tăng bộ đếm tại offset object
`0x60` khi pending đã tồn tại, rồi thay bằng frame mới ở `0x10003eec0`.
`videoSendInFlight` được kiểm tra ở `0x10003eed0`; chỉ đặt và dispatch drain khi
chưa có send đang chạy. Drain block `0x10003ef04` gọi
`drainVideoQueueForConnection:`.

Điều này chứng minh **một pending frame được thay bởi frame mới** trong đường
được khảo sát. Chưa đủ bằng chứng để khẳng định tất cả đường truyền xử lý partial
write đúng hoặc toàn bộ bộ nhớ transport luôn bounded. Các helper FBC framing
không chứng minh WebSocket; ScreenStream tự định nghĩa DKSS/1 qua RFC6455.

## Áp dụng vào source độc lập

ScreenStream tự triển khai IOSurface lifecycle, scale/rotation trước encode,
ImageIO, so sánh chính xác với frame encode thành công cuối, một encoder thread,
pool ba buffer, một frame pending và per-client output có offset partial write.
Khi pending bị thay, gói đang gửi dở được giữ nguyên để bảo toàn byte stream.
Không có viewer thì dừng capture/encode và trả tài nguyên.

Các quyết định này là source mới có kiểm thử, không phải bản đổi tên FarmBIOS.
Các khai báo Apple BSD và policy GPL tái dùng từ project hiện có được ghi công
trong `screenstream/ATTRIBUTION.md`. Hành vi và hiệu năng thực trên iPhone cần
kiểm thử riêng, không kế thừa kết quả giả định từ binary tham chiếu.
