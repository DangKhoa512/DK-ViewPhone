# ĐK ViewPhone 1.0.0

Bản tùy biến từ [TrollVNC](https://github.com/owngoal-dev/TrollVNC), dành riêng cho **Dopamine roothide**, iOS 15+, binary arm64 (iPhone 6s/7). Giữ engine capture và điều khiển gốc. Giấy phép GPLv2; xem [COPYING](COPYING) và [nguồn/ghi công](docs/ATTRIBUTION.md).

Mã nguồn phát triển: [DangKhoa512/DK-ViewPhone, dev/roothide](https://github.com/DangKhoa512/DK-ViewPhone/tree/dev/roothide).

## Build và tải DEB

Mở [Actions](https://github.com/DangKhoa512/DK-ViewPhone/actions/workflows/build-dkviewphone.yml), chọn **Build DK ViewPhone (roothide)** → **Run workflow** trên branch `dev/roothide`. Workflow cũng chạy khi push branch này.

Workflow build bản TrollVNC gốc trước, sau đó build ĐK ViewPhone, kiểm tra DEB và hash chữ ký ad-hoc Mach-O rồi mới upload artifact `DKViewPhone_1.0.0_roothide`. Bên trong có `DKViewPhone_1.0.0_roothide.deb`, SHA256SUMS, báo cáo kiểm tra và source của commit tương ứng. Artifact log luôn được upload khi build lỗi. Chỉ run màu xanh với bước kiểm tra thành công mới được coi là build đạt.

Build thủ công trên macOS với Xcode 16.2, `roothide/theos` cùng submodules, SDK 16.5/14.5 và dependencies như workflow:

```bash
export THEOS="$HOME/theos-roothide"
source devkit/roothide.sh
FINALPACKAGE=1 gmake clean package
python3 devkit/verify-package.py packages/com.dk.viewphone_1.0.0_iphoneos-arm64e.deb
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

Mặc định mới cài: server tắt; bind `127.0.0.1`; port `5901`; scale `0.75`; FPS `15:30:30`; clipboard và xoay màn hình bật; Bonjour và HTTP tắt; điều khiển chỉ sau xác thực.

- Mật khẩu full-access phải có đúng **8 ký tự ASCII nhìn thấy**, gồm chữ hoa, chữ thường, số và ký hiệu. Dùng mật khẩu ngẫu nhiên riêng. Không có mật khẩu mặc định. Mật khẩu view-only là tùy chọn và phải khác full-access, cùng quy tắc.
- Để dùng LAN, nhập **địa chỉ IPv4 Wi-Fi riêng của iPhone** vào Bind Address, ví dụ địa chỉ đang hiển thị trong Settings của máy. Bật Enabled, nhấn Apply khi sửa các thiết lập khác. Máy tính phải kết nối được tới cùng LAN.
- Trong VNC viewer, nhập host và port riêng `5901`. Với viewer dùng cú pháp cổng tuyệt đối, dùng `<IP-iPhone>::5901`; với macOS dùng `vnc://<IP-iPhone>:5901`. Nhập mật khẩu khi được hỏi.
- Nếu dùng SSH tunnel, giữ bind loopback và chuyển tiếp `ssh -N -L 5901:127.0.0.1:5901 mobile@<IP-iPhone>` rồi kết nối viewer tới `127.0.0.1:5901`. Cần SSH trên iPhone đã được cấu hình riêng.
- Classic VNC chỉ dùng 8 byte và không mã hóa hình ảnh/input. Dùng LAN tin cậy; trên mạng không tin cậy phải dùng tunnel mã hóa. Không forward cổng VNC ra Internet. IPv6, wildcard và bind IP công khai bị từ chối trong bản này.
- WebSocket/noVNC gốc vẫn có trong package; HTTP mặc định tắt, muốn bật phải cấu hình certificate/key. Dùng WSS/tunnel và kiểm tra TLS trên thiết bị trước khi sử dụng.
- Có thể tắt bằng Enabled hoặc Control Center. Server do LaunchDaemon quản lý, không phụ thuộc việc giữ Settings mở.

Các thiết lập cũ từ TrollVNC được giữ khi thay gói. Defaults mới áp dụng cho trường chưa lưu; mật khẩu cũ yếu khiến server bị tắt để cấu hình lại. Gỡ gói giữ lại preferences; có thể Reset Settings trước khi gỡ.

## Kiểm tra và giới hạn

`python3 -m unittest discover -s tests -v` kiểm tra source/plist/defaults và ba file engine được giữ nguyên. CI biên dịch/chạy `tests/security-policy.cpp`. Validator DEB kiểm tra metadata, payload, bundle, daemon, scripts, arm64, dependencies, entitlement và hash chữ ký, không chạy code trong DEB.

Đã thử DEB thật trên iPhone 6s / iOS 15.8.4 Dopamine roothide: capture, xác thực,
tap/vuốt, chặn tap/vuốt ở chế độ chỉ xem, kết nối lại, chạy khi đóng Settings và
gỡ/cài lại bằng dpkg đều đạt. Kết nối LAN trực tiếp chưa xác nhận do máy tính và
iPhone khác subnet. Xem [kết quả và giới hạn](docs/RUNTIME-RESULTS.md) cùng
[checklist thiết bị](docs/DEVICE-TESTS.md). Chữ ký ad-hoc hợp lệ không tương đương
chữ ký Apple/App Store. Xem [các thay đổi](docs/CHANGES.md) và [ghi chú dependency/source kế thừa](docs/ATTRIBUTION.md).
Tài liệu gốc được lưu tại [README.upstream.md](docs/README.upstream.md).
