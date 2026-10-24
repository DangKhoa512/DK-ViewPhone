# Hai engine độc lập và baseline đối chiếu

| Thuộc tính | ĐK ViewPhone | ĐK ScreenStream |
|---|---|---|
| Package | com.dk.viewphone | com.dk.screenstream |
| Engine | TrollVNC/LibVNCServer RFB | Native capture, ImageIO JPEG, WebSocket DKSS/1 |
| Worker | trollvncserver | dkss-server |
| Supervisor | dkviewphone-watchdog | dkss-supervisor |
| LaunchDaemon | com.82flex.trollvnc | com.dk.screenstream |
| Preferences | com.82flex.trollvnc | com.dk.screenstream |
| Viewer | noVNC, hiện có Multi View | Viewer JPEG riêng, chỉ xem |
| Cổng | RFB 5901, HTTP/WS 5801 | HTTP/WS 5802 |
| Trạng thái/log | DK ViewPhone hiện có | Library/Logs/DKScreenStream, recovery.json riêng |
| Input | Giữ tap/swipe/keyboard/clipboard hiện có | Chưa triển khai, từ chối lệnh input |

ViewPhone baseline build ngày 24/10 là commit
`ec6779efaf474229c7adf509a26d3b5d7869d195`, run
[40053842646](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/40053842646).
SHA-256 DEB `79a7d6643e5fb75698e8302f9654de03b5bf3e5e2de8ebc9c78ca1b9c29f11d1`.
Source VNC và HID không thay đổi trong quá trình thêm/fix ScreenStream; các
tối ưu ViewPhone trước ngày 24/10 được giữ trong baseline này.

`src/ScreenCapturer.mm` dùng CADisplayLink, dirty counter, CARenderServer,
IOSurface accelerator và CMSampleBuffer. Đường xử lý trong
`src/trollvncserver.mm` scale/rotation BGRA và publish framebuffer cho RFB;
Low Latency tái dùng workspace vImage, bỏ pixel trùng và đánh dấu vùng thay đổi
chính xác dưới khóa sender. LibVNCServer chọn encoding theo thương lượng client;
không được gọi toàn bộ engine là JPEG full-frame.

RFB có lợi thế cập nhật vùng nhỏ và chức năng điều khiển đang có; JPEG full-frame
có pipeline đơn giản và viewer riêng. Đây là khác biệt kiến trúc, không chứng minh
engine nào nhanh hơn. Preset/quality giữa hai encoding không tương đương trực tiếp.

Khi benchmark chỉ bật một engine, cùng iPhone/nội dung/LAN/client và ghi rõ scale,
kích thước thật, FPS mục tiêu, encoding, chất lượng, số viewer. Static screen có
FPS thấp do bỏ frame trùng; cần nội dung chuyển động có kiểm soát để đánh giá.
RTT ping khác độ trễ hiển thị; không lấy timestamp hai máy trừ nhau khi chưa đồng
bộ đồng hồ. Với một iPhone chỉ đánh giá một máy; farm nhiều máy vẫn NOT TESTED.

Baseline đã qua kiểm tra host, build iOS và kiểm tra DEB. Bảng đo thiết bị và các
mốc 30 phút/1 giờ/2 giờ sẽ được ghi theo dữ liệu thực trong báo cáo tiến độ.
Không xem build thành công là PASS capture/input/độ ổn định trên iPhone.
