# ĐK ViewPhone 1.3.0

[Chế độ LAN không mật khẩu 1.1.3](docs/PASSWORDLESS-LAN-1.1.3.md).

Bổ sung [LAN Web Viewer tích hợp trong DEB](docs/LAN-WEB-VIEWER.md) dạng dashboard một trang: lưới preview và panel điều khiển lớn hoạt động đồng thời.
Giữ các tính năng Stability 1.1.0. Xem [kết quả kiểm thử Web Viewer](docs/WEB-VIEWER-RESULTS.md).

Bản tùy biến từ [TrollVNC](https://github.com/owngoal-dev/TrollVNC), dành riêng cho **Dopamine roothide**, iOS 15+, binary arm64 (iPhone 6s/7). Giữ engine capture và điều khiển gốc. Giấy phép GPLv2; xem [COPYING](COPYING) và [nguồn/ghi công](docs/ATTRIBUTION.md).

Mã nguồn phát triển: [DangKhoa512/DK-ViewPhone, dev/roothide](https://github.com/DangKhoa512/DK-ViewPhone/tree/dev/roothide).

## Ứng dụng Desktop Windows

Thư mục [desktop](desktop/) chứa ứng dụng Electron tận dụng trực tiếp dashboard
Device Farm/noVNC hiện tại. Nút **Quét LAN** dò TCP 5801/5901 trong các subnet IPv4
riêng đang kết nối, thêm máy có cổng VNC 5901 vào grid, sau đó cho phép chọn
một máy để điều khiển trong panel lớn. Kết quả quét không tự kết nối; preview
và focus tiếp tục tuân theo giới hạn stream của dashboard.

Build thủ công bằng `cd desktop`, `npm ci`, `npm test`, `npm run build:win`, hoặc chạy
workflow **Build DK ViewPhone Desktop**. File portable là
`DKViewPhone_Desktop_1.0.1_x64.exe`; máy sử dụng không cần cài Node.js. Xem
[hướng dẫn Desktop](desktop/README.md).

## Build và tải DEB

Mở [Actions](https://github.com/DangKhoa512/DK-ViewPhone/actions/workflows/build-dkviewphone.yml), chọn **Build DK ViewPhone (roothide)** → **Run workflow** trên branch `dev/roothide`. Workflow cũng chạy khi push branch này.

Workflow build bản TrollVNC gốc trước, sau đó build ĐK ViewPhone, kiểm tra DEB và hash chữ ký ad-hoc Mach-O rồi mới upload artifact `DKViewPhone_1.3.0_roothide`. Bên trong có `DKViewPhone_1.3.0_roothide.deb`, SHA256SUMS, báo cáo kiểm tra và source của commit tương ứng. Artifact log luôn được upload khi build lỗi. Chỉ run màu xanh với bước kiểm tra thành công mới được coi là build đạt.

Build thủ công trên macOS với Xcode 16.2, `roothide/theos` cùng submodules, SDK 16.5/14.5 và dependencies như workflow:

```bash
export THEOS="$HOME/theos-roothide"
source devkit/roothide.sh
FINALPACKAGE=1 gmake clean package
python3 devkit/verify-package.py packages/com.dk.viewphone_1.3.0_iphoneos-arm64e.deb
```

Metadata `iphoneos-arm64e` là quy ước **package scheme roothide**, không có nghĩa binary chỉ chạy trên CPU arm64e. Binary trong bản này là arm64. Không dùng DEB này trên rootless thông thường hoặc TrollStore.

## Cài bằng Sileo

1. Tải artifact từ một run thành công, giải nén và đối chiếu SHA256SUMS.
2. Chuyển DEB sang iPhone, mở/chia sẻ bằng Sileo hoặc trình quản lý gói hỗ trợ cài DEB cục bộ. Nếu Sileo hiện tại không hỗ trợ mở file trực tiếp, dùng trình quản lý DEB tương thích trên máy; không đổi đuôi thành IPA.
3. Xem transaction: gói `com.dk.viewphone` sẽ **thay thế** `com.82flex.trollvnc`. Không cài song song hai gói.
4. Vào **Settings → ĐK ViewPhone**. Cấu hình mật khẩu và địa chỉ bind trước khi bật.

Nếu TrollVNC được cài riêng bằng TrollStore, hãy dừng server/manager của app đó
trước khi dùng DEB này. Không chạy đồng thời vì vẫn dùng chung preference domain
và tài nguyên dịch vụ; quan hệ thay thế gói không áp dụng cho app TrollStore.

## Kết nối máy tính

Mặc định mới cài: server tắt; bind `127.0.0.1`; VNC `5901`; Web `5801`; scale `0.40`; FPS `30:60:120`; ưu tiên độ trễ thấp, Web Viewer, LAN tin cậy, không mật khẩu LAN và điều khiển từ xa đều bật. Clipboard và xoay màn hình bật; Bonjour và HTTPS/WSS tắt. Trước khi bật server để dùng LAN, chọn IPv4 Wi-Fi riêng của iPhone làm Bind Address.

- Mật khẩu full-access phải có đúng **8 ký tự ASCII nhìn thấy**, gồm chữ hoa, chữ thường, số và ký hiệu. Dùng mật khẩu ngẫu nhiên riêng. Không có mật khẩu mặc định. Mật khẩu view-only là tùy chọn và phải khác full-access, cùng quy tắc.
- Để dùng LAN, nhập **địa chỉ IPv4 Wi-Fi riêng của iPhone** vào Bind Address, ví dụ địa chỉ đang hiển thị trong Settings của máy. Bật Enabled, nhấn Apply khi sửa các thiết lập khác. Máy tính phải kết nối được tới cùng LAN.
- Trong VNC viewer, nhập host và port riêng `5901`. Với viewer dùng cú pháp cổng tuyệt đối, dùng `<IP-iPhone>::5901`; với macOS dùng `vnc://<IP-iPhone>:5901`. Nhập mật khẩu khi được hỏi.
- Nếu dùng SSH tunnel, giữ bind loopback và chuyển tiếp `ssh -N -L 5901:127.0.0.1:5901 mobile@<IP-iPhone>` rồi kết nối viewer tới `127.0.0.1:5901`. Cần SSH trên iPhone đã được cấu hình riêng.
- Classic VNC chỉ dùng 8 byte và không mã hóa hình ảnh/input. Dùng LAN tin cậy; trên mạng không tin cậy phải dùng tunnel mã hóa. Không forward cổng VNC ra Internet. IPv6, wildcard và bind IP công khai bị từ chối trong bản này.
- Web Viewer dùng HTTP/WS mặc định và chỉ phù hợp LAN tin cậy. Dashboard lưu danh sách thiết bị, chế độ và cổng trên trình duyệt; không lưu mật khẩu. Preview luôn chỉ xem, còn panel focus nắm phiên điều khiển chính. HTTPS/WSS cần certificate/key phù hợp được trình duyệt tin cậy cho từng iPhone. Xem [cấu hình chi tiết](docs/LAN-WEB-VIEWER.md).
- Có thể tắt bằng Enabled hoặc Control Center. Server do LaunchDaemon quản lý, không phụ thuộc việc giữ Settings mở.

Các thiết lập cũ từ TrollVNC được giữ khi thay gói. Defaults mới áp dụng cho trường chưa lưu; mật khẩu cũ yếu khiến server bị tắt để cấu hình lại. Gỡ gói giữ lại preferences; có thể Reset Settings trước khi gỡ.

## Kiểm tra và giới hạn

Bản 1.1.0 thêm watchdog, phục hồi khi interface/IP thay đổi, giới hạn client gửi
chậm và diagnostic JSON có xoay log. Xem [thiết kế, rủi ro và kế hoạch kiểm tra](docs/STABILITY-1.1.0.md).
Test 24 giờ và reboot được để lại cho đợt sau theo yêu cầu chủ máy; không coi là đã đạt.
Xem [kết quả thực tế bản 1.1.0](docs/TEST-RESULTS-1.1.0.md): nâng cấp, 100 lần kết nối,
phục hồi lỗi, clipboard, respring và xoay ngang đã kiểm tra; 20 chu kỳ Wi-Fi cũng được hoãn.

`python3 -m unittest discover -s tests -v` kiểm tra source/plist/defaults và hai file capture/input được giữ nguyên.
CI biên dịch/chạy các bài C++ cho bảo mật, backoff/crash-loop và chống echo clipboard.
ClipboardManager có sửa nhỏ để không bỏ mất thay đổi mới và có polling dự phòng.
Validator DEB kiểm tra metadata, payload, bundle, daemon, scripts, arm64, dependencies,
entitlement và hash chữ ký, không chạy code trong DEB.

Đợt kiểm thử 1.0.0 đã thử DEB thật trên iPhone 6s / iOS 15.8.4 Dopamine roothide: capture, xác thực,
tap/vuốt, chặn tap/vuốt ở chế độ chỉ xem, kết nối lại, chạy khi đóng Settings và
gỡ/cài lại bằng dpkg đều đạt. Sau khi đưa PC và iPhone về chung LAN, kết nối VNC
trực tiếp qua Wi-Fi cũng đã đạt capture, tap/vuốt, chặn tap ở chế độ chỉ xem,
kết nối lại và từ chối mật khẩu sai. Xem [kết quả và giới hạn](docs/RUNTIME-RESULTS.md) cùng
[checklist thiết bị](docs/DEVICE-TESTS.md). Chữ ký ad-hoc hợp lệ không tương đương
chữ ký Apple/App Store. Xem [các thay đổi](docs/CHANGES.md) và [ghi chú dependency/source kế thừa](docs/ATTRIBUTION.md).
Tài liệu gốc được lưu tại [README.upstream.md](docs/README.upstream.md).
