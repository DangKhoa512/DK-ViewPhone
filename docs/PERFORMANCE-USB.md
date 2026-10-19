# Tối ưu luồng xem và USB — 19/10/2026

Các thay đổi dưới đây mới nằm trong mã nguồn. Chưa build EXE/DEB, cài lên iPhone
hoặc đo FPS và độ trễ trên điện thoại trong đợt này.

## Luồng ảnh trên Desktop

Mỗi mục thiết bị dùng một kết nối RFB cho cả preview và điều khiển. Khi mở focus,
canvas đang chạy được chuyển sang panel điều khiển; khi đóng thì chuyển trở lại.
Mật khẩu phiên, kết nối và ngân sách reconnect được giữ lại. Khung nhỏ của máy
đang focus lấy ảnh bằng `drawImage`, tối đa 10 lần/giây và rộng không quá 480 pixel;
không vẽ khi toàn màn hình, tab ẩn hoặc card ngoài vùng nhìn. Giới hạn này chỉ áp
dụng cho ảnh phụ cục bộ, không phải giới hạn FPS của luồng điều khiển.

Trong fixture RFB loopback cố định, hai preview và một focus giảm từ ba luồng về
hai luồng. Lưu lượng trong cửa sổ ba giây giảm khoảng 34,6%. Đây là phép đo Raw
giả lập, không có chi phí mã hóa Tight/JPEG của iPhone và không mô phỏng USB/Wi-Fi.
Xem [phương pháp và kết quả](PERFORMANCE-OFFLINE-2026-10-19.md).

## Xử lý ảnh phía iPhone

`ensureScaleTemp` tái sử dụng kết quả tính workspace khi kích thước nguồn/đích và
flags không đổi. Cấp phát lại kiểm tra lỗi trước khi khởi tạo bộ nhớ. Khi bật
Low Latency, ảnh thu nhỏ dùng bộ lọc Lanczos-3; khi tắt vẫn dùng Lanczos-5. Bộ lọc
nhẹ hơn có thể giảm nhẹ độ nét khi thu nhỏ. Kích thước xuất, màu và tọa độ input
không đổi. [Apple mô tả hai chế độ bộ lọc](https://developer.apple.com/documentation/accelerate/kvimagehighqualityresampling).

Debug hooks nay giữ cả runtime deadline/metrics như Release để lần benchmark
tiếp theo không vô tình bỏ cơ chế bảo vệ client gửi chậm. Không thay cadence FPS,
retry publication 33 ms, thuật toán capture hoặc HID. Thay đổi native chưa được
biên dịch/chạy vImage trên iOS trong môi trường Windows này; chưa có mức tăng FPS
thực tế để công bố.

## USB có nhanh hơn không?

USB có thể giúp khi Wi-Fi bị nhiễu, nghẽn hoặc có độ trễ biến động. Nó chỉ thay
đường truyền; iPhone vẫn phải chụp, scale và mã hóa ảnh VNC. Nếu CPU mã hóa đang
chiếm phần lớn thời gian, thay Wi-Fi bằng USB không tự khắc phục được nút thắt đó.

[Audit cũ](../PERFORMANCE.md) trên iPhone 15 Pro có Tight probe khoảng 67,62
updates/s qua USB/iproxy + SSH so với 32,26 qua LAN trên cùng server. Đó là yêu
cầu mã hóa lại framebuffer gần tĩnh, không phải FPS chuyển động, không phải phép
đo dashboard hiện tại và không suy rộng cho iPhone khác.

Chế độ USB trong Desktop dùng `127.0.0.1` và cổng forward đã cấu hình. Cắm cáp hoặc
chọn USB trong form không tự tạo cầu kết nối. Cần driver/Trust và công cụ chuyển
tiếp cổng như [iproxy](https://github.com/libimobiledevice/libusbmuxd/blob/master/docs/iproxy.1).
Mỗi iPhone dùng UDID và cổng local riêng. Ví dụ khi VNC nhận kết nối loopback trên
iPhone:

```text
iproxy -u <UDID_IPHONE_1> -l 15901:5901
iproxy -u <UDID_IPHONE_2> -l 15902:5901
```

Trong Desktop, chọn USB và lần lượt cổng 15901, 15902. Nếu VNC đang bind riêng IP
Wi-Fi thì forward loopback trực tiếp có thể không tới listener; dùng SSH qua USB
để chuyển tiếp tới đúng địa chỉ đang bind, hoặc cấu hình bind phù hợp trên máy.
HTTPS/WSS vẫn cần chứng chỉ phù hợp với endpoint; USB không thay quy tắc TLS.

## Phân biệt hai tỷ lệ ảnh

**Scale khung hình trên Desktop** chỉ đổi kích thước hiển thị, không giảm số pixel
iPhone gửi đi. **Output Scale trong Settings trên iPhone** mới đổi kích thước ảnh
được mã hóa: giảm cả hai chiều xuống 0,5 tương ứng một phần tư số pixel so với
native. Muốn so sánh FPS cần giữ cùng output scale, nội dung chuyển động, chất
lượng/encoding và số viewer, rồi đổi duy nhất Wi-Fi/USB. FPS cấu hình trong
Settings là mục tiêu capture, không phải số khung chắc chắn xuất hiện trên PC.
