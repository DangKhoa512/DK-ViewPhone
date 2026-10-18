# Độ trễ và cài đặt tiếng Việt — 1.1.3

Tiếp tục từ checkpoint `c99c897`, không đổi package ID, engine capture, thuật toán
chạm/vuốt hoặc chế độ xác thực. Chế độ LAN không mật khẩu đã bật được giữ lại.

Trong Cài đặt → ĐK ViewPhone có tùy chọn **Ưu tiên độ trễ thấp**, mặc định tắt.
Nếu muốn thử, bật tùy chọn rồi nhấn **Áp dụng**. Kết quả đo ngắn bên dưới chưa cho
thấy lợi ích, nên máy thử được để tắt tùy chọn sau kiểm tra.
Tùy chọn giữ FPS tối thiểu bằng FPS ưu tiên trong lúc có người xem, và giảm chờ
gộp bản cập nhật RFB từ 5 ms xuống 1 ms. Vẫn bỏ qua ảnh không đổi, dừng capture
khi không có người xem và giữ giới hạn cho client chậm. FPS tối thiểu cao hơn có
thể tăng mức dùng pin. Không tự thay tỷ lệ ảnh hoặc cấu hình FPS đã lưu.

Ở chế độ này, nếu client đang giữ khóa gửi ảnh thì capture giữ ảnh mới nhất trong
back buffer và thử gửi lại sau 33 ms, thay vì chặn main runloop. Không tạo hàng đợi
khung hình; lần thử lại vẫn gửi được thay đổi cuối cùng khi màn hình đã đứng yên.
Phiên gửi một bản cập nhật quá 1 giây bị đóng; bộ kiểm tra hạn chạy mỗi 100 ms khi
có bản cập nhật đang gửi. Tắt chế độ này giữ hạn 10 giây và chu kỳ kiểm tra 2 giây
cũ. Client rất chậm có thể cần kết nối lại khi bật chế độ độ trễ thấp.

Log `frame_processing_*` đo thời gian xử lý capture, không bao gồm khoảng chờ thử
gửi lại và không đại diện cho độ trễ từ lệnh chạm đến ảnh trên trình duyệt.

Giữ FPS ưu tiên khoảng 30 cho iPhone 6s là cấu hình đang được kiểm tra trong đợt
này; không mặc định ép 60 FPS. Tỷ lệ xuất ảnh trên máy thử giữ khoảng 0.5.

Cài đặt được Việt hóa cả nhãn, phần giải thích, lựa chọn, cảnh báo, quản lý thiết
bị kết nối và nút nhật ký. Không đổi ngôn ngữ hệ thống của iPhone.

Phép đo: cùng Chrome/PC/LAN, Máy tính dọc, tap từ 0 sang 2; theo dõi vùng số trên
canvas bằng cùng đồng hồ `performance.now()`. Mỗi lượt bỏ hai lần làm nóng rồi
lấy 12 mẫu, bao gồm 20 ms giữ chuột. Đây là độ trễ lệnh đến ảnh trình duyệt, chưa
phải phép đo vật lý từ ngón tay đến photon.

Kết quả thực tế ngày 18/10/2026 trên iPhone 6s iOS 15.8.4:

| Cấu hình cùng HTTPS/WSS, tỷ lệ ảnh ~30%, canvas 224×399 | Trung vị | P95 mẫu (12 mẫu) |
| --- | ---: | ---: |
| Tùy chọn tắt | 130,55 ms | 277,3 ms |
| Tùy chọn bật | 154,65 ms | 351,3 ms |

Chưa chứng minh được giảm độ trễ trong bài đo này. Không gộp các lượt HTTP/tỷ
lệ ảnh 50% trước đó vào so sánh này: giao thức, tỷ lệ ảnh và mạng PC đã thay đổi.
Mỗi lượt chỉ có 12 mẫu nên P95 mẫu chính là mẫu lớn nhất, chưa đủ để suy rộng.
Heartbeat ghi nhận hai client kết nối trong cả hai cửa sổ đo; bài này chưa cô
lập chỉ một viewer. Số đo lấy từ candidate `54b48e9`, trước bản sửa thoát worker.

Với tùy chọn bật, client cố tình không đọc ảnh bị đóng trong cửa sổ quan sát
1,67 giây; viewer Chrome còn lại nhận thao tác Máy tính 0 → 2 và giữ ảnh tĩnh
cuối cùng. 100 lượt WSS/không mật khẩu (50 ngắt thường, 50 ngắt đột ngột) hoàn
thành trong 65,62 giây, giữ nguyên PID worker và kết nối viewer chính.
Các quan sát này lấy từ candidate `54b48e9`.

[Build cuối đã chạy thành công](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39095534142)
· [DEB và source tương ứng](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39095534142/artifacts/12124850105)
· [Báo cáo kiểm thử](test-results/1.1.3/report.json).

DEB được kiểm tra độc lập trùng kết quả CI: package `com.dk.viewphone` 1.1.3,
roothide, 206 mục payload, bốn binary arm64 có CodeDirectory hợp lệ; 165 chuỗi
tiếng Việt và web assets khớp source. Nâng cấp trực tiếp 1.1.2 → 1.1.3 giữ nguyên
toàn bộ cấu hình tại thời điểm nâng cấp. Sau đó người dùng đổi HTTPS/chứng chỉ
và tỷ lệ ảnh; những lựa chọn mới này được giữ lại.

Candidate `54b48e9` phát sinh một SIGSEGV lúc đóng worker khi đổi cấu hình
(stack `rfbShutdownServer` → `rfbCloseClient`). Build cuối `26e3094` dùng `_exit`
để hệ điều hành thu hồi toàn bộ tài nguyên của worker thoát, tránh giải phóng
client đồng thời với các luồng VNC. Không đổi chính sách watchdog hoặc quy trình
khởi động lại. Kiểm thử host 20 lần thoát khi còn luồng gửi dữ liệu xác nhận
socket EOF, exit code 75 và không chạy destructor đồng thời.

Trên thiết bị thật, build cuối đã qua 10 lần đổi cấu hình khi WSS đang kết nối:
10/10 lần tự nối lại. Tiếp đó 100 lượt WSS (50 ngắt thường, 50 đột ngột, 10 lần
kiểm tra pixel ảnh thực) hoàn thành trong 82,65 giây, giữ nguyên PID và viewer
chính. Năm crash report tại mốc cài build cuối giữ nguyên sau kiểm tra; không có
recovery event mới trong cửa sổ supervisor cuối. Báo cáo vẫn lưu crash của
candidate trước. Đây là kết quả ngắn, không suy rộng thành cam kết 24 giờ.

Trạng thái cuối: máy chủ bật, LAN HTTPS/WSS không mật khẩu trên 5801/5901,
giữ chứng chỉ và tỷ lệ ảnh người dùng chọn; tùy chọn độ trễ thấp tắt. CFPreferences
và file plist khớp đủ 28 giá trị mong đợi. Đã xóa thư mục công cụ thử tạm trên
iPhone, giữ file TLS đang sử dụng và đóng cầu USB tạm trên Windows.

SHA256 DEB cuối: `d20fe698d7bd92926663a2f37fe6431adefa770dbe12754022c1b33f9d28aaab`.

Giới hạn: chưa nghiệm thu đầy đủ giao diện Settings tiếng Việt trên máy thật.
Bài view-only có thao tác đổi màn hình trong lúc kiểm tra nên không ghi PASS.
Chưa chạy lại Edge, clipboard, xoay màn hình, respring, chu kỳ Wi-Fi/IP của
iPhone, reboot hoặc 24 giờ. Không tuyên bố không có memory leak từ bài test ngắn.
