# Điều chỉnh DEB cho nhiều iPhone — 19/10/2026

Các thay đổi này đã được build thành DEB và qua kiểm tra GitHub Actions; xem
[kết quả build và tải artifact](DEB-BUILD-2026-10-19.md). Chưa build EXE hoặc đo FPS,
độ trễ, nhiệt độ hay tải nhiều iPhone thật trong đợt này.

## Mặc định và địa chỉ lắng nghe

- `BindHost=auto`, hoặc giá trị trống/chưa lưu: chọn IPv4 LAN riêng đang hoạt động,
  ưu tiên Wi-Fi `en0`, tiếp đến Ethernet/LAN. Bỏ qua cellular, VPN, loopback và IP
  công cộng khi tự chọn; không dùng địa chỉ wildcard.
- Nếu không có LAN phù hợp, dùng `127.0.0.1`. Watchdog theo dõi thay đổi địa chỉ,
  chờ mạng ổn định ba giây rồi khởi động lại worker trên IP mới. Thao tác này có
  thể làm viewer kết nối lại; không ghi IP tạm vào preferences hoặc tính thành
  lỗi crash. Địa chỉ trong danh sách máy trên PC vẫn cần cập nhật khi DHCP đổi IP.
- IP đã lưu thủ công được giữ. Muốn chuyển từ IP cũ sang tự động, nhập `auto` hoặc
  xóa nội dung ô Địa chỉ lắng nghe rồi Áp dụng. Nếu chuyển tiếp USB trực tiếp tới
  loopback trên iPhone, có thể chọn rõ `127.0.0.1`.
- `SingleNotifEnabled=false` và `ClientNotifsEnabled=false`: mặc định không tạo
  thông báo trạng thái, kết nối hoặc ngắt kết nối. Vẫn có thể bật lại trong Settings.
  Diagnostic phục vụ watchdog vẫn hoạt động.

Server vẫn mặc định tắt. Các thiết lập người dùng đã lưu được giữ khi nâng cấp.

## Nhịp ảnh và công việc được giảm

Mặc định `FrameRateSpec=30:30:30`, giữ output scale `0.40`. Nhịp mục tiêu 30 FPS
tránh yêu cầu capture ở 60–120 Hz trên mỗi máy khi chạy nhiều màn hình đồng thời.
Người dùng vẫn có thể nhập `60` hoặc khoảng FPS khác. Cấu hình này là mục tiêu
capture, không bảo đảm viewer nhận đủ số khung đó khi CPU hoặc mạng quá tải.

Sau khi scale/xoay, so sánh chính xác framebuffer mới với framebuffer hiện tại.
Nếu không đổi pixel nào, bỏ lần swap/đánh dấu cập nhật. Nếu có thay đổi, chỉ báo
vùng chữ nhật bao toàn bộ pixel đổi cho LibVNCServer. Thay đổi nhỏ như con trỏ,
đồng hồ hay một ô nhập liệu vì thế không mặc định yêu cầu mã hóa cả màn hình.
Cuộn trang hoặc video toàn màn hình vẫn có thể làm vùng cập nhật phủ toàn khung.
Không suy ra mức giảm băng thông cố định cho các nội dung này.

So sánh và publication thực hiện sau khi đã khóa các client gửi ảnh; không đọc
buffer bị ghi đồng thời. Giữ cơ chế chỉ giữ khung mới nhất, thử khóa không chặn
trong Low Latency và retry để gửi thay đổi cuối cùng khi màn hình ngừng chuyển động.
Giữ engine capture và HID gốc. Cache bộ nhớ scale và bộ lọc nhẹ hơn trong Low Latency
từ đợt tối ưu trước tiếp tục được sử dụng.

## Kiểm tra cần có trên thiết bị

Kiểm tra tại workspace Windows: 12/12 bài Python cho source/plist/defaults đạt;
bài Node kiểm tra phiên dashboard và `git diff --check` đạt. Các bài C/C++ cho
chọn IPv4 và vùng pixel đã chạy đạt trên CI Linux (sanitizer) và macOS. Build iOS,
kiểm tra DEB và đối chiếu checksum sau khi tải về cũng đạt; xem báo cáo build trên.

Kiểm tra trên iPhone: tự chọn IP khi mở máy/chưa có Wi-Fi, DHCP/đổi mạng, USB với
bind loopback, xoay màn hình, pixel ở mép ảnh, cập nhật cuối sau khi client nghẽn,
full/view-only và việc tắt thông báo. Đo cùng một nội dung chuyển động ở 1/5/10
máy, giữ nguyên scale, encoding và chất lượng; theo dõi FPS thực, CPU/RAM và nhiệt.
Các bài test host kiểm chứng logic chọn địa chỉ và vùng pixel, không thay thế các
kiểm tra này trên iPhone.

Tham khảo API: [LibVNCServer đánh dấu vùng thay đổi](https://github.com/LibVNC/libvncserver/blob/master/src/libvncserver/main.c),
[Apple CADisplayLink preferredFrameRateRange](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange).
