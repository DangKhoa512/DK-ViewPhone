# Độ trễ và cài đặt tiếng Việt — 1.1.3

Tiếp tục từ checkpoint `c99c897`, không đổi package ID, engine capture, thuật toán
chạm/vuốt hoặc chế độ xác thực. Chế độ LAN không mật khẩu đã bật được giữ lại.

Trong Cài đặt → ĐK ViewPhone, bật **Ưu tiên độ trễ thấp**, rồi **Áp dụng**.
Tùy chọn giữ FPS tối thiểu bằng FPS ưu tiên trong lúc có người xem, và giảm chờ
gộp bản cập nhật RFB từ 5 ms xuống 1 ms. Vẫn bỏ qua ảnh không đổi, dừng capture
khi không có người xem và giữ giới hạn cho client chậm. FPS tối thiểu cao hơn có
thể tăng mức dùng pin. Không tự thay tỷ lệ ảnh hoặc cấu hình FPS đã lưu.

Giữ FPS ưu tiên khoảng 30 cho iPhone 6s là cấu hình đang được kiểm tra trong đợt
này; không mặc định ép 60 FPS. Tỷ lệ xuất ảnh trên máy thử giữ khoảng 0.5.

Cài đặt được Việt hóa cả nhãn, phần giải thích, lựa chọn, cảnh báo, quản lý thiết
bị kết nối và nút nhật ký. Không đổi ngôn ngữ hệ thống của iPhone.

Phép đo: cùng Chrome/PC/LAN, Máy tính dọc, tap từ 0 sang 2; theo dõi vùng số trên
canvas bằng cùng đồng hồ `performance.now()`. Mỗi lượt bỏ hai lần làm nóng rồi
lấy 12 mẫu, bao gồm 20 ms giữ chuột. Đây là độ trễ lệnh đến ảnh trình duyệt, chưa
phải phép đo vật lý từ ngón tay đến photon. Kết quả trước/sau và kiểm thử thiết
bị thật sẽ cập nhật sau build; chưa xác nhận mức cải thiện tại thời điểm này.
