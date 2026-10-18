# ĐK ViewPhone Desktop

Ứng dụng Windows bọc dashboard noVNC 1.3.0 hiện tại bằng Electron. Giao diện
không có quyền Node.js; preload chỉ cung cấp một lệnh quét LAN giới hạn.

Bản 1.0.1 dùng bố cục console phone-farm gọn: lưới thiết bị đánh số ở bên trái,
màn hình điều khiển lớn ở giữa và rail thao tác bên phải. Card hiển thị IP, trạng thái
kết nối và viền màu để có thể theo dõi nhiều máy trên màn hình desktop rộng.

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
3. Nhấn **Kết nối** trên card để xem preview; double-click card hoặc nhấn
   **Mở điều khiển** để chuyển máy đó sang panel focus.
4. Dùng **Chỉ xem**, **Tự co giãn** và **Toàn màn hình** trong thanh công cụ.

Scanner chỉ chấp nhận IPv4 riêng và giới hạn mỗi card mạng ở /24, tối đa
bốn subnet. Mật khẩu VNC không được lưu xuống ổ đĩa. Một số router bật AP/client
isolation sẽ chặn PC truy cập iPhone dù hai máy cùng tên Wi-Fi; khi đó cần tắt
isolation hoặc dùng VLAN/LAN cho phép client giao tiếp trực tiếp.
