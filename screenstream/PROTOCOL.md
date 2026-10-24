# DKSS/1

Protocol độc lập, không phải RFB hoặc giao thức tương thích FarmBIOS.

WebSocket `/stream` phải RFC6455 version 13; frame client được mask. Sau handshake,
client gửi text JSON `{"type":"auth","token":"<mã 64 ký tự hex>"}` trong năm giây.
Không có frame hình ảnh trước khi xác thực. Tối đa bốn viewer, tối đa 32 TCP
connection bao gồm HTTP/chưa xác thực. Client không đọc bị ngắt sau năm giây nghẽn.

Server trả JSON `{"type":"ready","protocol":1,"viewOnly":true,"input":false}`.
Sau đó mỗi WS binary message chứa chính xác một header big-endian và một JPEG.

| Offset | Kiểu | Giá trị |
|---:|---|---|
| 0 | 4 byte | ASCII `DKSS` |
| 4 | uint8 | Version 1 |
| 5 | uint8 | JPEG flag 1 |
| 6 | uint16 | Header length 40 |
| 8 | uint64 | Sequence tăng theo JPEG được tạo |
| 16 | uint64 | Monotonic microseconds tại đầu capture |
| 24 | uint32 | Pixel width |
| 28 | uint32 | Pixel height |
| 32 | uint16 | Rotation đã áp dụng: 0/90/180/270 độ |
| 34 | uint16 | Reserved 0 |
| 36 | uint32 | JPEG byte length |
| 40 | bytes | JPEG, tối đa 4 MiB |

Pixel đã xoay; viewer không xoay lần nữa theo metadata. Timestamp không phải Unix
time và không dùng trực tiếp để tính latency giữa đồng hồ PC/iPhone khác nhau.

Heartbeat: WS ping/pong mỗi 15 giây, mất hoạt động 45 giây đóng kết nối. Ứng dụng
viewer gửi `{"type":"ping","t":<performance.now()>}`; server echo `pong` và `t`
để đo RTT bằng cùng đồng hồ client. JSON command tối đa 4096 byte, fragmented
message cũng chịu tổng giới hạn đó. Control frame tối đa 125 byte và FIN bắt buộc.
Phiên không hỗ trợ input; lệnh ngoài auth/ping hợp lệ bị đóng với code 1008.

Metrics JSON: framesCaptured, framesEncoded, framesSkipped, framesDropped,
captureErrors, encodeErrors, captureTotalMs, encodeTotalMs, outputBytes,
socketBytes, viewers. `framesSkipped` gồm dirty/compare trùng. `framesDropped`
đếm cơ hội/frame bỏ do pool/queue/transport, có thể đếm nhiều delivery khi nhiều
viewer; không dùng nó làm FPS hoặc tỷ lệ mất frame độc lập với stage.
`socketBytes` gồm HTTP/WS overhead; `outputBytes` chỉ gồm JPEG được encoder tạo.
Thời gian tổng là tích lũy để tính trung bình/delta, không phải latency màn hình.

HTTP/WS không có TLS trong phiên bản này. Bearer token có thể bị phát lại nếu bị
lộ; dùng LAN tin cậy hoặc SSH. Không quảng bá replay protection hoặc mã hóa chưa
triển khai. Không truyền token qua query string, log hay browser storage.
