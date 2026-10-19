# ĐK ViewPhone Desktop

Ứng dụng Windows bọc dashboard noVNC 1.3.0 hiện tại bằng Electron. Giao diện
không có quyền Node.js; preload chỉ cung cấp một lệnh quét LAN giới hạn.

Bản 1.0.3 dùng giao diện xám tối với thanh công cụ trên cùng để thêm thiết bị,
quét LAN và tìm kiếm. Bảng **Hiển thị** bên phải chứa kích thước khung preview,
số cột và giới hạn phiên live. Tên thiết bị nằm bên trái, trạng thái kết nối nằm
bên phải ngay trên ảnh preview. Bấm đúp vào khung thiết bị để mở màn hình điều
khiển lớn với thanh công cụ phía dưới. Khi xem toàn màn hình, mở menu **☰** rồi
chọn biểu tượng bút chì để sửa thông tin thiết bị. Khung preview/focus tự bám tỷ lệ
framebuffer khi xoay máy. Lưới mặc định có năm cột, giới hạn mặc định và tối đa
là 10 phiên live.

Mỗi thiết bị dùng chung một phiên kết nối cho preview và màn hình điều khiển.
Khi mở điều khiển, ảnh nhỏ của cùng thiết bị là bản sao cục bộ, cập nhật tối đa
10 lượt/giây và tạm dừng khi xem toàn màn hình. Chuyển hoặc đóng màn hình điều
khiển giữ phiên đang kết nối; thao tác **Ngắt** vẫn dừng phiên đó.

Thanh **Scale khung hình** điều chỉnh kích thước preview từ 50% đến 150%, mỗi bước
5%, mặc định 100%. Khung giữ nguyên tỷ lệ ảnh của thiết bị khi phóng to, thu nhỏ
hoặc xoay màn hình. Thiết lập được lưu trên máy tính; độ phân giải ảnh từ iPhone
và kết nối LAN/USB giữ nguyên.

## Chạy phát triển

```powershell
cd desktop
npm install
npm start
```

Nút **Quét LAN** kiểm tra TCP 5801/5901 trên tối đa bốn subnet IPv4 riêng,
mỗi subnet bị giới hạn ở /24. Máy có VNC 5901 được thêm vào grid nhưng không tự
kết nối. Danh sách thiết bị tiếp tục được lưu bằng storage key của Web Viewer;
mật khẩu chỉ nằm trong bộ nhớ phiên.

## Build Windows

```powershell
cd desktop
npm run test
npm run build:win
```

Artifact portable nằm trong `desktop/dist/`. Không cần cài Node.js trên máy
chạy file EXE. Bản portable chưa có chữ ký Authenticode nên Windows có thể hiện
cảnh báo nhà phát hành không xác định.

## Sử dụng

1. Bật server và **LAN Web Viewer** trên từng iPhone; cổng mặc định là
   HTTP 5801 và VNC 5901.
2. Nối PC và iPhone vào cùng LAN, mở app rồi nhấn **Quét LAN**.
3. Bấm vào khung thiết bị để xem preview; bấm đúp để mở màn hình điều khiển lớn.
   Biểu tượng ở góc dưới bên phải khung mở thiết bị ở chế độ toàn màn hình.
4. Menu **☰** chứa **Chỉ xem**, **Tự co giãn** và thao tác kết nối lại/ngắt kết nối.
   Chỉnh **Scale khung hình**, số cột và giới hạn live trong bảng **Hiển thị** bên phải.
5. Trong chế độ toàn màn hình, mở menu **☰** và chọn biểu tượng bút chì để
   đổi tên hoặc thông tin kết nối của thiết bị.

Scanner chỉ chấp nhận IPv4 riêng và giới hạn mỗi card mạng ở /24, tối đa
bốn subnet. Mật khẩu VNC không được lưu xuống ổ đĩa. Một số router bật AP/client
isolation sẽ chặn PC truy cập iPhone dù hai máy cùng tên Wi-Fi; khi đó cần tắt
isolation hoặc dùng VLAN/LAN cho phép client giao tiếp trực tiếp.
