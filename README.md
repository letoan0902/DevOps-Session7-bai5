# DevOps - Session 07 - Bài 5: Chẩn đoán và xử lý xung đột cổng mạng (Address Already in Use)

Bài tập xử lý sự cố Spring Boot không khởi động được vì cổng 8082 bị một tiến trình chạy ngầm chiếm giữ. Quy trình gồm: tái hiện lỗi, tìm PID bằng `ss`, `lsof`, `fuser`, kiểm tra tiến trình bằng `ps` và `/proc`, giải phóng cổng bằng `kill`, khởi động lại `spring-app.service` và xác nhận cổng 8082 do `java` (`app.jar`) quản lý.

Báo cáo nộp bài: [homework/session_07/ex5/troubleshoot_report.md](homework/session_07/ex5/troubleshoot_report.md)

## Danh sách file

| File | Nội dung |
|---|---|
| `homework/session_07/ex5/troubleshoot_report.md` | Báo cáo chính: chuỗi lệnh đã gõ, bảng thông tin tiến trình, giải trình quy trình chẩn đoán |
| `homework/session_07/ex5/terminal_log.txt` | Toàn bộ log phiên làm việc trên terminal |
| `homework/session_07/ex5/free_port.sh` | Script bash giải phóng một cổng TCP (SIGTERM, chờ, SIGKILL nếu cần) |
| `homework/session_07/ex5/README.md` | Mô tả ngắn bài tập |
