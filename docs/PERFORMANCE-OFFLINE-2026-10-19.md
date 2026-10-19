# Đo mô phỏng cục bộ ngày 19/10/2026

Kiểm tra Chrome headless trên Windows với HTTP và hai RFB/WebSocket fixture chỉ
lắng nghe tại `127.0.0.1`. Không quét LAN, kết nối iPhone, thay cấu hình điện thoại
hoặc build EXE. Fixture trả ảnh Raw 120×214 thay đổi theo sequence, giới hạn
20 bản cập nhật/giây cho mỗi socket. Đây là dữ liệu tổng hợp, không phải FPS của
iPhone, FPS hiển thị vật lý hay benchmark encoder Tight/JPEG.

Baseline gồm bundle, HTML và hai CSS được sao chép trước khi sửa vào
`artifacts/perf-baseline/webclients/`, có hash trong `manifest.json`.
SHA-256 bundle baseline:
`cf159744023447aa75121304e6e7ec80718ec65f08b7b3be194a29b32445a626`.
Bundle sau thay đổi:
`20a81edfe2326ee52a384db078ec6a008575da810c32bbc250368fc035b9b40c`.

Hai thiết bị A/B đã xem preview; sau đó mở điều khiển A, đo một cửa sổ khoảng
ba giây với cùng fixture:

| Quan sát khi điều khiển A | Baseline | Sau thay đổi |
| --- | ---: | ---: |
| Socket đang truyền A / B | 2 / 1 | 1 / 1 |
| Canvas noVNC thực | 3 | 2 |
| Canvas sao chép cục bộ | 0 | 1 |
| Thời gian quan sát | 3,007 giây | 3,003 giây |
| Byte WebSocket gửi trong cửa sổ | 16.336.614 | 10.685.584 |
| Bản cập nhật framebuffer gửi | 159 | 104 |
| Số lần vẽ bản sao preview | 0 | 28 |

Lượng byte giảm khoảng 34,6% trong cửa sổ này do bỏ một luồng trùng của A.
Canvas noVNC ban đầu được giữ nguyên khi mở, chuyển và đóng điều khiển; không
có handshake mới ở các thao tác đó. Canvas thứ ba sau thay đổi chỉ là bản sao
cục bộ, khoảng 9,3 lần vẽ/giây trong bài đo, không có socket hay decoder riêng.

CDP `TaskDuration` tăng 0,1878 giây ở baseline và 0,1357 giây sau thay đổi trong
hai cửa sổ trên. Đây là tổng thời gian task trên main thread của Chrome trong
một lượt ngắn, không phải kết quả CPU ổn định hoặc phép đo CPU iPhone. Chưa có
đo lặp đủ dài để khẳng định mức cải thiện CPU hoặc độ trễ thực tế.

Các kiểm tra tích hợp đạt:

- Giữ socket và đúng canvas khi focus A → B → đóng; thiết bị còn lại tiếp tục
  nhận ảnh. Preview sau khi đóng điều khiển chặn input.
- **Chỉ xem** chặn chuột và bàn phím; bỏ chọn gửi input tới đúng fixture.
- Bản sao preview cập nhật tối đa 10 lần/giây và dừng trong fullscreen.
- Đổi tên, kể cả trong fullscreen, giữ socket/canvas và trạng thái fullscreen.
- Đổi endpoint và ngắt socket đột ngột chỉ kết nối lại thiết bị bị tác động.
- Giới hạn 1, 2 và 10 phiên được giữ khi mở và đóng điều khiển.
- Không có lỗi trang hoặc lỗi giao thức fixture trong lượt đạt cuối.

Công cụ cục bộ: `.tools/perf-offline-qa.py`; kết quả:
`artifacts/perf-offline/baseline.json`, `current.json` và `after-fixture.png`.
Các thư mục công cụ/artifact này được git bỏ qua. Một lần thử sau thay đổi dừng
vì tọa độ click của fixture trùng nhãn tên thiết bị; đã sửa fixture để click giữa
ảnh rồi chạy lại toàn bộ. Báo cáo lần đó được giữ trong
`current-fixture-coordinate-attempt.json`, không được tính là lỗi ứng dụng.

Phép đo này không kiểm chứng đường truyền USB/LAN thật, mức dùng pin, FPS/độ trễ
trên iPhone hoặc thay đổi xử lý ảnh native. Các kết quả thiết bị cũ trong
`PERFORMANCE.md` và báo cáo 1.1.x/1.3.0 là các môi trường khác, cần đọc riêng.
