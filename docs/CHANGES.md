# ĐK ViewPhone changes

## Đang phát triển — tối ưu Desktop/DEB

- Dùng chung một kết nối RFB cho preview và điều khiển mỗi thiết bị; ảnh preview phụ sao chép cục bộ khi đang điều khiển. Giới hạn live tối đa 10.
- DEB mặc định `BindHost=auto`, ưu tiên IPv4 Wi-Fi hiện tại và tự chọn lại khi mạng thay đổi; giữ địa chỉ đã nhập thủ công.
- Mặc định tắt thông báo trạng thái và lịch sử kết nối. Giữ tùy chọn bật lại và giữ giá trị người dùng đã lưu.
- Mặc định capture `30:30:30`, scale `0.40`; chỉ đánh dấu vùng pixel thực sự thay đổi, bỏ cập nhật framebuffer giống nhau. Giữ lựa chọn FPS cao hơn.
- Xem [chi tiết và giới hạn kiểm chứng](DEB-FARM-TUNING.md). [DEB đã build/kiểm tra đạt trên CI](DEB-BUILD-2026-10-19.md); chưa build EXE hoặc đo tải nhiều điện thoại cho các thay đổi này.

## 1.3.0

- Thay Single View/Multi View bằng dashboard một trang kiểu phone farm: lưới thiết bị luôn hiển thị và panel điều khiển lớn mở bên phải hoặc dạng overlay trên màn hình hẹp.
- Click chọn card, double-click hoặc nút Điều khiển mở Focus Panel; có chuyển máy trước/sau, chọn nhanh, fullscreen, View Only và Auto Scale mà không reload trang.
- Preview và focus dùng RFB instance độc lập. Preview luôn chỉ xem và dùng chất lượng thấp hơn; focus được ưu tiên chất lượng và một slot live khi đạt giới hạn.
- Tiếp tục lazy-load theo viewport, giới hạn 1–12 phiên, reconnect 2/4/8/16/16 giây, cô lập lỗi từng máy và giữ các stream khác khi đổi máy focus.
- Thêm lưới 2/3/4/5 cột, số máy online/live trên top bar, tìm kiếm/lọc, ngắt toàn bộ và dữ liệu mẫu offline để kiểm tra bố cục.
- Giữ storage key 1.2.0 để không mất danh sách thiết bị. Mật khẩu chỉ nằm trong bộ nhớ phiên và không được ghi vào localStorage.

## 1.2.0

- Thêm Single View và Multi View 2/3/4 cột, quản lý thiết bị LAN/USB, tìm kiếm, lọc, kết nối theo lựa chọn và mở card sang màn hình điều khiển lớn.
- Mỗi card dùng RFB riêng, reconnect exponential backoff, timeout riêng, lazy connection theo vùng nhìn và giới hạn mặc định 6 Live View.
- Danh sách thiết bị được lưu trong trình duyệt; mật khẩu chỉ giữ trong bộ nhớ tab và không ghi vào localStorage hay source.
- Đặt mặc định cài mới: Low Latency bật, LAN không mật khẩu bật, scale 0.40, FPS 30:60:120, Web Viewer/LAN tin cậy/điều khiển từ xa bật, HTTP 5801.
- Dừng đóng gói tweak thay đồng hồ bằng IPv4 theo yêu cầu; thanh trạng thái iOS giữ nguyên.

## 1.1.4

- Chuyển thông báo kết nối/ngắt kết nối sang mức ẩn: không biểu ngữ và không âm thanh.
- Thêm lựa chọn LAN/USB trong Web Viewer; USB hỗ trợ cổng chuyển tiếp riêng cho từng iPhone.
- Thay đồng hồ giữa thanh trạng thái bằng IPv4 hiện tại trong SpringBoard.
- Giới hạn kiểm thử tải thiết bị ở tối đa 10 phiên theo mô hình một PC điều khiển nhiều iPhone.

## 1.1.3

Adds optional low-latency scheduling: 1 ms RFB update batching instead of 5 ms,
and capture's minimum cadence equal to the configured preferred FPS while
viewers are connected. Dirty-frame skipping, zero-viewer stop, image scale,
gesture coordinates and authentication modes are retained.
Existing preferences keep the old scheduling unless this option is enabled.
In low-latency mode, a busy sender defers publication of the latest back buffer
without blocking the main runloop; one retry preserves the final static change.
The send deadline is 1 second with a 100 ms active sweep, instead of the retained
10 second/2 second defaults. Slow viewers may reconnect. Idle polling is unchanged.

Fixes a device-observed exit-time crash in rfbShutdownServer/rfbCloseClient when
live configuration changes terminate a worker. The exiting worker delegates
resource reclamation to the kernel with _exit, avoiding concurrent engine-client
destruction and C++ TLS-registry destructors. Restart policy and persistent logs
remain in the existing supervisor; no in-process engine restart is introduced.

Vietnamese Settings covers labels, explanations, option lists, alerts, client
actions and log controls. Preference keys/defaults and existing values are
retained. Build checks validate formatting placeholders and packaged translations.
Device before/after latency results are recorded separately; no FPS or latency
claim is inferred from configuration alone.

## 1.1.2

Adds explicit optional passwordless LAN mode at the owner's request. Reuses
LibVNCServer security type None; default remains password authentication. The
new mode requires Trusted LAN consent, a concrete private/loopback IPv4 bind,
and Reverse Mode off. Existing credentials are retained. Global view-only,
Remote Control restriction and blocked-host checks still apply. The web client
opens a password dialog only when challenged by the server.
See [setup and actual results](PASSWORDLESS-LAN-1.1.2.md).

## 1.1.1

Integrates an offline blue LAN Web Viewer around the bundled noVNC. Reuses
LibVNCServer HTTP and native WS/WSS; adds a bounded optional native HTTPS static
adapter because the built-in HTTP service has no TLS support. Adds Settings for
web opt-in, explicit trusted-LAN consent, HTTPS, remote-control restriction,
current IP, web URL and Copy URL. Defaults to web off and HTTP port 5801.
Resolves certificate/key/custom document-root paths at the prebuilt-library
boundary with libroothide, preserving saved logical or physical path values.
Fixes automatic reconnect after established server-side WebSocket closes.
Hardens the inherited OpenSSL adapter against concurrent read/write/close,
and releases unused WebSocket request paths before session threads start to
avoid the 0.9.15 repeated-close double-free found on the physical device.
Concurrent TLS lifecycle regression runs under ASan/UBSan in CI.

The 1.1.0 capture/input, clipboard, watchdog/backoff, network recovery and runtime
metrics implementations are retained. The HTTP CONNECT proxy is disabled because
the viewer uses native WebSocket on the VNC port. No new server runtime or
production entitlements are added. See [setup](LAN-WEB-VIEWER.md) and
[recorded tests and limits](WEB-VIEWER-RESULTS.md).

## 1.1.0

Adds a separate bounded-recovery supervisor, main-runloop heartbeat, private
interface rebinding, per-update slow socket deadline, TCP keepalive and bounded
JSON diagnostics with CPU/RSS/changed-frame metrics. Fixes client publication
lock lifetime, callback autorelease scope, realloc failure handling and clipboard
echo suppression/missed notifications. Saved preference values and the server's
security policy/entitlements remain unchanged. Capture and HID injection files
remain byte-for-byte identical to upstream.

See [audit and design](STABILITY-1.1.0.md) and [physical results](TEST-RESULTS-1.1.0.md).
The owner deferred 24-hour, reboot and 20 Wi-Fi-cycle checks.

## 1.0.0

Baseline: owngoal-dev/TrollVNC cfdb737e72977d961eb7d0a8110d2fe1a58551d7.

- `Makefile`: version, roothide-only device packaging, explicit libroothide link.
- `layout/DEBIAN/{control,postinst,prerm}`: package identity, controlled replacement
  of TrollVNC, RootHide virtual paths, visible installation errors.
- `devkit/roothide.sh`: honor an explicit Theos checkout and detect a missing one.
- `devkit/before-package.sh`: bundle GPL/attribution and reject Managed.plist.
- `.github/workflows/build-dkviewphone.yml`: pinned upstream/Theos baseline,
  macOS/Xcode, original build first, derivative build second, validate before
  artifact upload, always retain diagnostics. Original workflow is archived as
  `docs/upstream-build.yml` so other schemes cannot run accidentally.
- `src/trollvncserver.mm`, `src/DKViewPhonePolicy.h`: display/defaults, mandatory
  eight-byte mixed ASCII credentials, distinct view-only credential, explicit
  private/loopback IPv4 bind, disable wildcard IPv6 listener, TLS configuration
  for web access, no keyboard logging, per-client input/clipboard protections.
- `src/BulletinManager.mm`: notification display title only.
- `app/TrollVNC/TrollVNC/ZTSelfSignedCertificate.m`: replace the iOS 15 deprecated
  SecKeyGeneratePair with SecKeyCreateRandomKey/SecKeyCopyPublicKey, retaining
  RSA-2048 generation and certificate export.
- `app/TrollVNC/TrollVNC/{TVNCRootListController.m,TVNCUtil.h}` and
  `prefs/CCTrollVNC/CCTrollVNC.mm`: shared Settings/CC password checks and stop
  behavior. The DEB compiles these through the existing source symlinks.
  Reset Defaults also stops an existing session before reloading the disabled
  default configuration.
- `prefs/*/Makefile`, preference/CC plist and localization resources: arm64/iOS15,
  display names and editable defaults. Upstream self-updater is compiled only
  for bootstrap apps, which this project explicitly excludes.
- `devkit/verify-package.py`, `tests/*`: source consistency, engine preservation,
  security policy, real DEB and Mach-O signature checks.
- `.gitattributes`, `.gitignore`: portable shell line endings and build exclusions.
- `Artworks/DKViewPhone.svg`, `devkit/generate-icons.ps1`, preference/CC PNGs:
  native brand artwork and transparent Control Center glyphs.
- `layout/usr/share/trollvnc/webclients/index.vnc`: display branding and WSS as
  the default browser connection action; noVNC engine files are unchanged.
- `README.md`, `docs/*`: setup, provenance, limitations, device test checklist.
- `docs/third-party/*`: preserved library/client/font license texts and download
  provenance, copied into the DEB documentation directory.

Internal identifiers intentionally preserved: executable `trollvncserver`,
daemon label/preference domain `com.82flex.trollvnc`, resource directory
`usr/share/trollvnc`, bundles `TrollVNCPrefs`/`CCTrollVNC` and their identifiers.
Package-level Conflicts/Replaces/Provides ensure these files do not coexist
with the original package. Existing preferences survive replacement; invalid
credentials disable startup. Removing the package keeps user preferences.

ScreenCapturer.mm, STHIDEventGenerator.mm and ClipboardManager.mm are unchanged.
No capture, rotation, scaling or gesture algorithms were rewritten. Existing
entitlements and static libraries are unchanged.
