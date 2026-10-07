# Session 07 - Bài 5: Xử lý xung đột cổng 8082 (Address Already in Use)

## Mục tiêu

- Chẩn đoán các cổng đang lắng nghe trên Linux bằng `ss`, `lsof`, `fuser` (và `netstat` nếu đã cài `net-tools`).
- Dùng `ps`, `/proc` để xác định tiến trình đang chiếm cổng, dùng `kill` (và `kill -9` khi cần) để giải phóng.
- Xử lý lỗi `Address already in use` khi triển khai `spring-app.service` (Spring Boot, cổng 8082).

## Nội dung báo cáo

`troubleshoot_report.md` ghi lại theo thứ tự thời gian:

1. Hiện trạng: dịch vụ đang dừng, cổng 8082 trống.
2. Giả lập: `python3 -m http.server 8082 > /dev/null 2>&1 &` (PID 24102).
3. Tái hiện lỗi: Spring Boot báo `Port 8082 was already in use`, `systemd` khởi động lại liên tục.
4. Chẩn đoán: `ss`, `lsof`, `fuser`, `ps`, `/proc`.
5. Giải phóng: `kill 24102`, kiểm tra cổng đã trống.
6. Khôi phục: `reset-failed`, `restart`, xác nhận cổng 8082 do `java` (PID 24250) lắng nghe.
7. Giải trình quy trình 6 bước, bảng xử lý sự cố, bảng đối chiếu yêu cầu đề.

## File trong thư mục

| File | Mô tả |
|---|---|
| `troubleshoot_report.md` | Báo cáo chính nộp bài |
| `terminal_log.txt` | Log toàn bộ phiên làm việc |
| `free_port.sh` | Script giải phóng cổng: `sudo ./free_port.sh [--yes] [--timeout GIÂY] CỔNG` |

## Kiểm tra nhanh kết quả

```bash
sudo ss -tlnp | grep 8082
sudo lsof -i :8082
```

Kết quả mong đợi: cổng 8082 được lắng nghe bởi tiến trình `java` (chạy `app.jar`), không phải tiến trình giả lập.
