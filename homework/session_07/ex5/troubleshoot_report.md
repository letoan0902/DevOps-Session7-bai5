# BÁO CÁO CHẨN ĐOÁN VÀ XỬ LÝ XUNG ĐỘT CỔNG 8082 (ADDRESS ALREADY IN USE)

Session 07 - Bài 5: Chẩn đoán cổng mạng, giải phóng cổng bị chiếm và khởi động lại `spring-app.service`.

| Hạng mục | Nội dung |
|---|---|
| Máy chủ | `halo` (103.116.104.228), Ubuntu 24.04.3 LTS, kernel 6.8.0-87-generic, systemd 255 |
| Người thực hiện | user `devops` (uid 1001, nhóm sudo), đăng nhập SSH qua cổng 2222 |
| Thời gian | 2026-10-08, 10:30 đến 11:05 (UTC+07) |
| Dịch vụ bị ảnh hưởng | `spring-app.service` (Spring Boot 3.3.4, OpenJDK 21.0.4), chạy bằng user `java-runner`, lắng nghe `127.0.0.1:8082` |
| Sự cố | Cổng 8082 bị một tiến trình chạy ngầm chiếm giữ, Spring Boot báo `Port 8082 was already in use` và không khởi động được |
| Kết quả | Tìm ra PID 24102 (`python3 -m http.server 8082`), tắt bằng `kill`, dịch vụ chạy lại với PID 24250 và giữ cổng 8082 |

## 1. Tóm tắt

Mọi lệnh bên dưới gõ trên tài khoản `devops` ở thư mục home; toàn bộ phiên nằm trong `terminal_log.txt`.

- Dịch vụ `spring-app.service` đang được dừng để bảo trì từ 10:12:44 nên cổng 8082 trống.
- Trong lúc kiểm tra, tôi chạy thử `python3 -m http.server 8082` ở nền (PID 24102) và quên tắt. Cổng bị chiếm.
- Khi bật lại dịch vụ, Java thoát với mã 1 và `systemd` khởi động lại liên tục mỗi 10 giây. Tôi dừng vòng lặp, dùng `ss`, `lsof`, `fuser` để tìm PID, dùng `ps` và `/proc` để xác nhận đó là tiến trình của chính mình, rồi `kill 24102`.
- Sau `reset-failed` và `restart`, cổng 8082 do `java` (PID 24250, `app.jar`) lắng nghe, `/health` trả `UP`, Nginx trả 200 thay vì 502.

## 2. Hiện trạng ban đầu (trước sự cố)

```text
devops@halo:~$ date
Thu Oct  8 10:31:04 +07 2026
devops@halo:~$ systemctl status spring-app.service --no-pager -n 3
o spring-app.service - Spring Boot Application
     Loaded: loaded (/etc/systemd/system/spring-app.service; enabled; preset: enabled)
     Active: inactive (dead) since Thu 2026-10-08 10:12:44 +07; 18min ago
   Duration: 4h 41min 9.318s
        CPU: 1min 9.402s

Oct 08 10:12:44 halo systemd[1]: spring-app.service: Deactivated successfully.
Oct 08 10:12:44 halo systemd[1]: Stopped spring-app.service - Spring Boot Application.
Oct 08 10:12:44 halo systemd[1]: spring-app.service: Consumed 1min 9.402s CPU time.
devops@halo:~$ sudo ss -tlnp | grep 8082; echo "exit=$?"
[sudo] password for devops: 
exit=1
devops@halo:~$ curl -I http://localhost/api/health
HTTP/1.1 502 Bad Gateway
Server: nginx/1.24.0 (Ubuntu)
Date: Thu, 08 Oct 2026 03:31:49 GMT
Content-Type: text/html
Content-Length: 166
Connection: keep-alive
```

- `inactive (dead)` là trạng thái sau `systemctl stop` có chủ ý để bảo trì, không phải lỗi.
- `grep` không có dòng khớp nên trả mã thoát 1 (`exit=1`): không có socket nào lắng nghe cổng 8082. Lần `sudo` đầu tiên hỏi mật khẩu, các lần sau trong 15 phút không hỏi lại.
- Nginx trả `502 Bad Gateway` vì `proxy_pass http://127.0.0.1:8082/` kết nối bị từ chối: backend không chạy.

## 3. Giả lập cổng 8082 bị chiếm

```text
devops@halo:~$ python3 --version
Python 3.12.3
devops@halo:~$ python3 -m http.server 8082 > /dev/null 2>&1 &
[1] 24102
devops@halo:~$ jobs -l
[1]+ 24102 Running                 python3 -m http.server 8082 > /dev/null 2>&1 &
devops@halo:~$ curl -I http://127.0.0.1:8082/
HTTP/1.0 200 OK
Server: SimpleHTTP/0.6 Python/3.12.3
Date: Thu, 08 Oct 2026 03:33:41 GMT
Content-type: text/html; charset=utf-8
Content-Length: 1843

devops@halo:~$ curl -I http://localhost/api/health
HTTP/1.1 404 File not found
Server: nginx/1.24.0 (Ubuntu)
Date: Thu, 08 Oct 2026 03:33:58 GMT
Content-Type: text/html;charset=utf-8
Content-Length: 335
Connection: keep-alive
```

- Dấu `&` đưa tiến trình xuống nền, bash in `[1] 24102` (số job và PID). Đầu ra bị chuyển vào `/dev/null` nên không thấy gì trên terminal, đúng với tình huống "chạy ngầm" của đề bài.
- Tiến trình do user `devops` chạy và `http.server` mặc định bind `0.0.0.0:8082` (mọi địa chỉ IPv4), khác với Spring Boot chỉ bind `127.0.0.1:8082`. Hai địa chỉ khác nhau vẫn xung đột vì cùng cổng: Linux không cho bind địa chỉ cụ thể khi đã có socket `LISTEN` trên địa chỉ wildcard của cùng cổng.
- Header `Server: SimpleHTTP/0.6 Python/3.12.3` chứng minh cổng đang do một tiến trình lạ phục vụ.
- Qua Nginx, `/api/health` (được chuyển thành `/health`) lúc này nhận `404 File not found` từ Python thay vì `502`. Đây là điểm nguy hiểm: backend sai nhưng hệ thống vẫn "có phản hồi".

## 4. Tái hiện lỗi `Address already in use`

```text
devops@halo:~$ sudo systemctl start spring-app.service
devops@halo:~$ systemctl status spring-app.service --no-pager -n 7
* spring-app.service - Spring Boot Application
     Loaded: loaded (/etc/systemd/system/spring-app.service; enabled; preset: enabled)
     Active: activating (auto-restart) (Result: exit-code) since Thu 2026-10-08 10:36:06 +07; 5s ago
    Process: 24128 ExecStart=/usr/bin/java -jar /opt/spring-app/app.jar (code=exited, status=1/FAILURE)
   Main PID: 24128 (code=exited, status=1/FAILURE)
        CPU: 4.108s

Oct 08 10:36:06 halo java[24128]: Description:
Oct 08 10:36:06 halo java[24128]: Web server failed to start. Port 8082 was already in use.
Oct 08 10:36:06 halo java[24128]: Action:
Oct 08 10:36:06 halo java[24128]: Identify and stop the process that's listening on port 8082 or configure this application to listen on another port.
Oct 08 10:36:06 halo systemd[1]: spring-app.service: Main process exited, code=exited, status=1/FAILURE
Oct 08 10:36:06 halo systemd[1]: spring-app.service: Failed with result 'exit-code'.
Oct 08 10:36:06 halo systemd[1]: spring-app.service: Consumed 4.108s CPU time.
```

Xem 40 dòng log cuối của dịch vụ (30 dòng chưa đủ chứa trọn một vòng lỗi, nên tôi lấy 40 dòng; 7 dòng đầu là lần dừng bảo trì lúc 10:12):

```text
devops@halo:~$ sleep 5; journalctl -u spring-app.service -n 40 --no-pager
Oct 08 10:12:43 halo systemd[1]: Stopping spring-app.service - Spring Boot Application...
Oct 08 10:12:43 halo java[23871]: 2026-10-08T10:12:43.207+07:00  INFO 23871 --- [ionShutdownHook] o.s.b.w.e.tomcat.GracefulShutdown        : Commencing graceful shutdown. Waiting for active requests to complete
Oct 08 10:12:43 halo java[23871]: 2026-10-08T10:12:43.212+07:00  INFO 23871 --- [tomcat-shutdown] o.s.b.w.e.tomcat.GracefulShutdown        : Graceful shutdown complete
Oct 08 10:12:43 halo java[23871]: 2026-10-08T10:12:43.240+07:00  INFO 23871 --- [ionShutdownHook] o.apache.catalina.core.StandardService   : Stopping service [Tomcat]
Oct 08 10:12:44 halo systemd[1]: spring-app.service: Deactivated successfully.
Oct 08 10:12:44 halo systemd[1]: Stopped spring-app.service - Spring Boot Application.
Oct 08 10:12:44 halo systemd[1]: spring-app.service: Consumed 1min 9.402s CPU time.
Oct 08 10:36:02 halo systemd[1]: Started spring-app.service - Spring Boot Application.
Oct 08 10:36:03 halo java[24128]:   .   ____          _            __ _ _
Oct 08 10:36:03 halo java[24128]:  /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
Oct 08 10:36:03 halo java[24128]: ( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
Oct 08 10:36:03 halo java[24128]:  \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
Oct 08 10:36:03 halo java[24128]:   '  |____| .__|_| |_|_| |_\__, | / / / /
Oct 08 10:36:03 halo java[24128]:  =========|_|==============|___/=/_/_/_/
Oct 08 10:36:03 halo java[24128]:  :: Spring Boot ::                (v3.3.4)
Oct 08 10:36:03 halo java[24128]: 2026-10-08T10:36:03.318+07:00  INFO 24128 --- [           main] com.example.springapp.SpringApp          : Starting SpringApp v1.0.0 using Java 21.0.4 with PID 24128 (/opt/spring-app/app.jar started by java-runner in /opt/spring-app)
Oct 08 10:36:03 halo java[24128]: 2026-10-08T10:36:03.325+07:00  INFO 24128 --- [           main] com.example.springapp.SpringApp          : No active profile set, falling back to 1 default profile: "default"
Oct 08 10:36:04 halo java[24128]: 2026-10-08T10:36:04.012+07:00  INFO 24128 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port 8082 (http)
Oct 08 10:36:04 halo java[24128]: 2026-10-08T10:36:04.019+07:00  INFO 24128 --- [           main] o.apache.catalina.core.StandardService   : Starting service [Tomcat]
Oct 08 10:36:04 halo java[24128]: 2026-10-08T10:36:04.020+07:00  INFO 24128 --- [           main] o.apache.catalina.core.StandardEngine    : Starting Servlet engine: [Apache Tomcat/10.1.30]
Oct 08 10:36:04 halo java[24128]: 2026-10-08T10:36:04.071+07:00  INFO 24128 --- [           main] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring embedded WebApplicationContext
Oct 08 10:36:04 halo java[24128]: 2026-10-08T10:36:04.072+07:00  INFO 24128 --- [           main] w.s.c.ServletWebServerApplicationContext : Root WebApplicationContext: initialization completed in 746 ms
Oct 08 10:36:06 halo java[24128]: 2026-10-08T10:36:06.201+07:00  INFO 24128 --- [           main] o.apache.catalina.core.StandardService   : Stopping service [Tomcat]
Oct 08 10:36:06 halo java[24128]: 2026-10-08T10:36:06.209+07:00  WARN 24128 --- [           main] ConfigServletWebServerApplicationContext : Exception encountered during context initialization - cancelling refresh attempt: org.springframework.context.ApplicationContextException: Failed to start bean 'webServerStartStop'; nested exception is org.springframework.boot.web.server.PortInUseException: Port 8082 is already in use
Oct 08 10:36:06 halo java[24128]: 2026-10-08T10:36:06.223+07:00  INFO 24128 --- [           main] .s.b.a.l.ConditionEvaluationReportLogger : 
Oct 08 10:36:06 halo java[24128]: Error starting ApplicationContext. To display the condition evaluation report re-run your application with 'debug' enabled.
Oct 08 10:36:06 halo java[24128]: 2026-10-08T10:36:06.236+07:00 ERROR 24128 --- [           main] o.s.b.d.LoggingFailureAnalysisReporter   : 
Oct 08 10:36:06 halo java[24128]: ***************************
Oct 08 10:36:06 halo java[24128]: APPLICATION FAILED TO START
Oct 08 10:36:06 halo java[24128]: ***************************
Oct 08 10:36:06 halo java[24128]: Description:
Oct 08 10:36:06 halo java[24128]: Web server failed to start. Port 8082 was already in use.
Oct 08 10:36:06 halo java[24128]: Action:
Oct 08 10:36:06 halo java[24128]: Identify and stop the process that's listening on port 8082 or configure this application to listen on another port.
Oct 08 10:36:06 halo systemd[1]: spring-app.service: Main process exited, code=exited, status=1/FAILURE
Oct 08 10:36:06 halo systemd[1]: spring-app.service: Failed with result 'exit-code'.
Oct 08 10:36:06 halo systemd[1]: spring-app.service: Consumed 4.108s CPU time.
Oct 08 10:36:16 halo systemd[1]: spring-app.service: Scheduled restart job, restart counter is at 1.
Oct 08 10:36:16 halo systemd[1]: Stopped spring-app.service - Spring Boot Application.
Oct 08 10:36:16 halo systemd[1]: Started spring-app.service - Spring Boot Application.
```

Kiểm tra cấu hình khởi động lại của systemd:

```text
devops@halo:~$ systemctl show spring-app.service -p Restart,RestartUSec,NRestarts,ActiveState,SubState,StartLimitIntervalUSec,StartLimitBurst
Restart=on-failure
RestartUSec=10s
NRestarts=2
ActiveState=activating
SubState=auto-restart
StartLimitIntervalUSec=5min
StartLimitBurst=5
```

Cách đọc log:

- Banner và `Starting SpringApp ... with PID 24128`: JVM đã chạy. `Tomcat initialized with port 8082 (http)`: Tomcat nhúng chuẩn bị bind cổng 8082, sau đó bind thất bại nên có `Stopping service [Tomcat]` và `PortInUseException`.
- Khối `APPLICATION FAILED TO START` là phần phân tích lỗi của Spring Boot: `Description` nêu nguyên nhân (cổng đã bị dùng), `Action` gợi ý hướng xử lý (tìm và tắt tiến trình đang giữ cổng hoặc đổi cổng).
- `status=1/FAILURE` và `Failed with result 'exit-code'`: JVM thoát với mã 1, `Restart=on-failure` nên systemd lập lịch chạy lại sau `RestartSec=10`. Mỗi vòng mất khoảng 14 giây (4 giây khởi động và thất bại, 10 giây chờ). `Scheduled restart job, restart counter is at 1` là lần khởi động lại đầu tiên (`NRestarts=2` ở thời điểm kiểm tra sau đó).

Vì sao phải dừng dịch vụ trước khi chẩn đoán: nếu để vòng lặp chạy, cứ 14 giây lại có một JVM khởi động, tốn khoảng 4 giây CPU và ghi hàng chục dòng log, làm nhiễu `journalctl` và `ss`. Ngoài ra `StartLimitBurst=5` trong `StartLimitIntervalSec=300` chỉ cho phép 5 lần khởi động trong 300 giây; lần thứ 6 (khoảng 10:37:13) sẽ bị chặn với `Failed with result 'start-limit-hit'`, dịch vụ chuyển sang `failed` và phải `reset-failed` mới chạy lại được. Tôi dừng sau lần khởi động thứ 3:

```text
devops@halo:~$ sudo systemctl stop spring-app.service
devops@halo:~$ systemctl is-active spring-app.service
inactive
devops@halo:~$ pgrep -a java; echo "exit=$?"
exit=1
```

`pgrep -a java` không in gì (`exit=1`): không còn JVM nào chạy, cổng 8082 chỉ còn bị Python giữ.

## 5. Chẩn đoán: tìm tiến trình chiếm cổng 8082

```text
devops@halo:~$ sudo ss -tlnp | grep 8082
LISTEN 0      5            0.0.0.0:8082       0.0.0.0:*    users:(("python3",pid=24102,fd=3))
devops@halo:~$ sudo lsof -i :8082
COMMAND   PID   USER   FD   TYPE  DEVICE SIZE/OFF NODE NAME
python3 24102 devops   3u   IPv4  183274      0t0  TCP *:8082 (LISTEN)
devops@halo:~$ netstat -tlnp | grep 8082
Command 'netstat' not found, but can be installed with:
sudo apt install net-tools
devops@halo:~$ sudo fuser 8082/tcp
8082/tcp:            24102
devops@halo:~$ sudo fuser -v 8082/tcp
                     USER        PID ACCESS COMMAND
8082/tcp:            devops    24102 F.... python3
devops@halo:~$ sudo lsof -t -i :8082
24102
```

Ý nghĩa các tham số của `ss` (và `netstat`):

| Tham số | Ý nghĩa |
|---|---|
| `-t` | chỉ xét socket TCP |
| `-l` | chỉ liệt kê socket đang lắng nghe (LISTEN) |
| `-n` | hiển thị số thay vì phân giải tên (8082 thay vì tên dịch vụ, IP thay vì tên máy) |
| `-p` | hiển thị tiến trình sở hữu socket; cần `sudo` để thấy tiến trình của user khác |

Cách đọc từng kết quả:

- `ss`: `LISTEN` là trạng thái; `0` là Recv-Q (với socket LISTEN là số kết nối đang chờ accept); `5` là Send-Q (với socket LISTEN là kích thước hàng đợi backlog); `0.0.0.0:8082` là địa chỉ và cổng cục bộ (mọi địa chỉ); `0.0.0.0:*` là địa chỉ đối tác (chưa có); `users:(("python3",pid=24102,fd=3))` cho biết tên tiến trình, PID và file descriptor số 3. PID nằm ở cột cuối trong ngoặc đơn.
- `lsof -i :8082`: `-i :8082` chọn các file mạng ở cổng 8082. Cột `FD` = `3u` là descriptor 3 mở đọc và ghi; `TYPE` = `IPv4`; `NAME` = `*:8082 (LISTEN)` nghĩa là bind mọi địa chỉ. Thêm `-t` chỉ in PID, tiện cho script.
- `netstat`: máy chưa cài gói `net-tools` nên báo `Command 'netstat' not found`. Tôi không cài thêm vì `ss` (gói `iproute2`, có sẵn) thay thế được hoàn toàn và tránh thay đổi hệ thống ngoài phạm vi bài. Nếu đã cài, `sudo netstat -tlnp | grep 8082` cho dòng tương đương với cột cuối dạng `24102/python3`.
- `fuser 8082/tcp`: in các PID đang dùng cổng; `-v` thêm user và cột `ACCESS` (`F` là file đang mở).

Ba công cụ cho cùng một kết quả: PID 24102, tiến trình `python3`, user `devops`.

## 6. Xem thông tin tiến trình trước khi quyết định tắt

```text
devops@halo:~$ ps -fp 24102
UID          PID    PPID  C STIME TTY          TIME CMD
devops     24102   23996  0 10:33 pts/0    00:00:00 python3 -m http.server 8082
devops@halo:~$ ps -o pid,ppid,user,etime,cmd -p 24102
    PID    PPID USER         ELAPSED CMD
  24102   23996 devops         06:22 python3 -m http.server 8082
devops@halo:~$ ps -o lstart= -p 24102
Thu Oct  8 10:33:20 2026
devops@halo:~$ cat /proc/24102/cmdline | tr '\0' ' '; echo
python3 -m http.server 8082 
devops@halo:~$ ls -l /proc/24102/cwd /proc/24102/exe
lrwxrwxrwx 1 devops devops 0 Oct  8 10:40 /proc/24102/cwd -> /home/devops
lrwxrwxrwx 1 devops devops 0 Oct  8 10:40 /proc/24102/exe -> /usr/bin/python3.12
devops@halo:~$ ps -p 23996 -o pid,comm
    PID COMMAND
  23996 bash
```

- `ps -fp` cho UID, PID, PPID, thời điểm bắt đầu (STIME) và dòng lệnh. `PPID` là 23996, tiến trình `bash` của phiên SSH hiện tại, không phải PID 1 (systemd). Vì vậy đây là tiến trình chạy tay từ shell, không thuộc dịch vụ nào.
- `/proc/24102/cmdline` ngăn cách tham số bằng ký tự NUL nên dùng `tr '\0' ' '` để đọc; `cwd` cho biết thư mục làm việc, `exe` cho biết file thực thi thật.

Thông tin ghi nhận:

| Mục | Giá trị |
|---|---|
| PID | 24102 |
| PPID | 23996 (bash của phiên SSH devops) |
| User | devops |
| Lệnh | `python3 -m http.server 8082` |
| File thực thi | `/usr/bin/python3.12` |
| Thư mục làm việc | `/home/devops` |
| Thời điểm khởi chạy | 2026-10-08 10:33:20 (đã chạy 06:22 lúc kiểm tra) |
| Địa chỉ lắng nghe | `0.0.0.0:8082` (IPv4, mọi địa chỉ), fd 3 |
| Người chịu trách nhiệm | chính user `devops` (tôi), chạy thử nghiệm trên cổng dịch vụ và quên tắt |
| Kết luận | an toàn để tắt: tiến trình của chính mình, không do systemd quản lý, không phải dịch vụ thật, không chứa dữ liệu cần giữ |

## 7. Giải phóng cổng

```text
devops@halo:~$ kill 24102
devops@halo:~$ sleep 2
[1]+  Terminated              python3 -m http.server 8082 > /dev/null 2>&1
devops@halo:~$ ps -p 24102; echo "exit=$?"
    PID TTY          TIME CMD
exit=1
devops@halo:~$ sudo ss -tlnp | grep 8082; echo "exit=$?"
exit=1
devops@halo:~$ jobs -l
```

- `kill 24102` gửi SIGTERM (tín hiệu 15), cho tiến trình cơ hội dọn dẹp và thoát êm. `sleep 2` chờ nó thoát; bash báo `Terminated` vào lần hiện prompt kế tiếp.
- `ps -p 24102` chỉ in tiêu đề và trả mã 1: PID không còn tồn tại. `ss | grep` rỗng, mã 1: cổng 8082 đã trống.

Khi nào dùng `kill -9`:

| Tình huống | Hành động |
|---|---|
| Tiến trình còn sau khi đã `kill <PID>` và chờ 5 đến 10 giây (bỏ qua hoặc kẹt khi xử lý SIGTERM) | `kill -9 <PID>` (tương đương `kill -KILL`) |
| Tiến trình của user khác hoặc của root | thêm `sudo`: `sudo kill -9 <PID>` |
| Tiến trình ở trạng thái `D` (chờ I/O trong kernel) | `kill -9` cũng không có tác dụng, phải xử lý nguyên nhân I/O hoặc khởi động lại |

Cảnh báo: không dùng `kill -9` ngay từ đầu. SIGKILL không thể bắt, tiến trình không kịp đóng file, xả bộ đệm, giải phóng khóa hay thông báo cho tiến trình con; với dịch vụ thật có thể gây mất dữ liệu hoặc để lại file khóa. Thứ tự đúng là `kill` (SIGTERM), chờ, kiểm tra bằng `ps`, rồi mới `kill -9`.

Cách làm tổng quát (không cần chép PID bằng tay), không chạy trong phiên này vì cổng đã trống:

```text
sudo kill $(sudo lsof -t -i :8082)     # SIGTERM tới mọi PID giữ cổng
sudo fuser -k 8082/tcp                 # tương tự, fuser -k mặc định gửi SIGKILL
sudo fuser -k -TERM 8082/tcp           # gửi SIGTERM thay vì SIGKILL
```

Nếu tiến trình chiếm cổng là một dịch vụ systemd có `Restart=`, `kill` chỉ làm nó sống lại sau vài giây; khi đó dùng `sudo systemctl stop <tên dịch vụ>`. Script `free_port.sh` đi kèm bài gói toàn bộ quy trình trên (liệt kê, hỏi xác nhận, SIGTERM, chờ, SIGKILL, kiểm tra lại).

## 8. Khởi động lại `spring-app.service`

```text
devops@halo:~$ sudo systemctl reset-failed spring-app.service
devops@halo:~$ sudo systemctl restart spring-app.service
devops@halo:~$ systemctl status spring-app.service --no-pager -n 3
* spring-app.service - Spring Boot Application
     Loaded: loaded (/etc/systemd/system/spring-app.service; enabled; preset: enabled)
     Active: active (running) since Thu 2026-10-08 10:43:41 +07; 12s ago
   Main PID: 24250 (java)
      Tasks: 25 (limit: 4551)
     Memory: 231.4M (peak: 232.0M)
        CPU: 5.203s
     CGroup: /system.slice/spring-app.service
             `-24250 /usr/bin/java -jar /opt/spring-app/app.jar

Oct 08 10:43:42 halo java[24250]: 2026-10-08T10:43:42.464+07:00  INFO 24250 --- [           main] w.s.c.ServletWebServerApplicationContext : Root WebApplicationContext: initialization completed in 684 ms
Oct 08 10:43:44 halo java[24250]: 2026-10-08T10:43:44.968+07:00  INFO 24250 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8082 (http) with context path ''
Oct 08 10:43:44 halo java[24250]: 2026-10-08T10:43:44.990+07:00  INFO 24250 --- [           main] com.example.springapp.SpringApp          : Started SpringApp in 3.218 seconds (process running for 3.742)
devops@halo:~$ journalctl -u spring-app.service -n 8 --no-pager
Oct 08 10:43:41 halo java[24250]: 2026-10-08T10:43:41.779+07:00  INFO 24250 --- [           main] com.example.springapp.SpringApp          : No active profile set, falling back to 1 default profile: "default"
Oct 08 10:43:42 halo java[24250]: 2026-10-08T10:43:42.401+07:00  INFO 24250 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port 8082 (http)
Oct 08 10:43:42 halo java[24250]: 2026-10-08T10:43:42.408+07:00  INFO 24250 --- [           main] o.apache.catalina.core.StandardService   : Starting service [Tomcat]
Oct 08 10:43:42 halo java[24250]: 2026-10-08T10:43:42.409+07:00  INFO 24250 --- [           main] o.apache.catalina.core.StandardEngine    : Starting Servlet engine: [Apache Tomcat/10.1.30]
Oct 08 10:43:42 halo java[24250]: 2026-10-08T10:43:42.463+07:00  INFO 24250 --- [           main] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring embedded WebApplicationContext
Oct 08 10:43:42 halo java[24250]: 2026-10-08T10:43:42.464+07:00  INFO 24250 --- [           main] w.s.c.ServletWebServerApplicationContext : Root WebApplicationContext: initialization completed in 684 ms
Oct 08 10:43:44 halo java[24250]: 2026-10-08T10:43:44.968+07:00  INFO 24250 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8082 (http) with context path ''
Oct 08 10:43:44 halo java[24250]: 2026-10-08T10:43:44.990+07:00  INFO 24250 --- [           main] com.example.springapp.SpringApp          : Started SpringApp in 3.218 seconds (process running for 3.742)
```

- `reset-failed` xóa trạng thái lỗi (`Result: exit-code`) và bộ đếm giới hạn khởi động (`StartLimit*`) của unit. Sau chuỗi thất bại ở mục 4 bước này đảm bảo `systemd` không từ chối khởi động với `start-limit-hit`. Lệnh không in gì khi thành công.
- `restart` khởi động unit (nếu đang dừng thì tương đương `start`). Lần này `Tomcat started on port 8082 (http)` và `Started SpringApp in 3.218 seconds`: bind thành công.
- `Main PID: 24250 (java)` và CGroup chứa đúng `/usr/bin/java -jar /opt/spring-app/app.jar`, tiến trình do systemd quản lý.

## 9. Xác nhận cổng 8082 đã chuyển sang `java`

```text
devops@halo:~$ sudo ss -tlnp | grep 8082
LISTEN 0      100        127.0.0.1:8082       0.0.0.0:*    users:(("java",pid=24250,fd=14))
devops@halo:~$ sudo lsof -i :8082
COMMAND   PID        USER   FD   TYPE  DEVICE SIZE/OFF NODE NAME
java    24250 java-runner  14u   IPv4  191377      0t0  TCP localhost:8082 (LISTEN)
devops@halo:~$ ps -fp 24250
UID          PID    PPID  C STIME TTY          TIME CMD
java-ru+   24250       1  8 10:43 ?        00:00:06 /usr/bin/java -jar /opt/spring-app/app.jar
devops@halo:~$ curl -s http://127.0.0.1:8082/health; echo
{"status":"UP","app":"spring-app","version":"1.0.0"}
devops@halo:~$ curl -sI http://127.0.0.1:8082/health
HTTP/1.1 200 
Content-Type: application/json
Content-Length: 52
Date: Thu, 08 Oct 2026 03:44:58 GMT

devops@halo:~$ curl -I http://localhost/api/health
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Date: Thu, 08 Oct 2026 03:45:36 GMT
Content-Type: application/json
Content-Length: 52
Connection: keep-alive

devops@halo:~$ date
Thu Oct  8 10:45:51 +07 2026
```

So sánh trước và sau:

| Tiêu chí | Trước (giả lập) | Sau (khôi phục) |
|---|---|---|
| Tiến trình giữ cổng | `python3`, PID 24102 | `java`, PID 24250 (`app.jar`) |
| User | `devops` | `java-runner` |
| Địa chỉ bind | `0.0.0.0:8082` | `127.0.0.1:8082` |
| Send-Q (backlog) | 5 (mặc định `http.server`) | 100 (hàng đợi của Tomcat) |
| Quản lý bởi | shell của devops | systemd (`spring-app.service`) |
| `/api/health` qua Nginx | 502, sau đó 404 | 200 |

Kết quả khớp kỳ vọng của đề: cổng 8082 được lắng nghe bởi tiến trình `java` chạy `app.jar`, không còn tiến trình giả lập. Header của `/health` không còn `Server: SimpleHTTP`, và Nginx trả 200 qua `/api/health`.

## 10. Giải trình quy trình chẩn đoán (6 bước)

```text
 [1] Phát hiện lỗi        journalctl: "Port 8082 was already in use"
          |
          v
 [2] Xác định cổng        8082/TCP (server.port=8082)
          |
          v
 [3] Tìm PID              ss -tlnp / lsof -i :8082 / fuser  ->  PID 24102
          |
          v
 [4] Xem tiến trình       ps -fp, /proc/PID  ->  python3, user devops, từ 10:33:20
          |
          v
 [5] Quyết định và tắt    kill (SIGTERM) -> chờ -> kill -9 chỉ khi cần
          |
          v
 [6] Khôi phục, xác minh  reset-failed, restart, ss/lsof, curl /health
```

| Bước | Việc làm | Vì sao |
|---|---|---|
| 1. Phát hiện lỗi | Đọc `systemctl status` và `journalctl`, thấy `PortInUseException` | Phân biệt xung đột cổng với lỗi cấu hình, thiếu file hay hết bộ nhớ; log nêu rõ số cổng |
| 2. Xác định cổng | Lấy cổng 8082 từ log và cấu hình | Biết chính xác cần tìm ai đang giữ cổng nào |
| 3. Tìm PID | `sudo ss -tlnp`, đối chiếu bằng `lsof`, `fuser` | Dùng `sudo` để thấy cả tiến trình của user khác; ba công cụ cho cùng PID thì kết quả đáng tin |
| 4. Xem tiến trình | `ps`, `/proc/PID/*`, PPID, user, thời điểm chạy | Tránh tắt nhầm dịch vụ quan trọng; PPID khác 1 và user `devops` cho thấy đây là tiến trình tự chạy |
| 5. Quyết định và tắt | `kill 24102`, kiểm tra `ps` và `ss` | Gửi SIGTERM trước để thoát êm; chỉ dùng `kill -9` khi SIGTERM không hiệu quả |
| 6. Khôi phục và xác minh | `reset-failed`, `restart`, kiểm tra `ss`, `lsof`, `curl` | Chứng minh đúng tiến trình `java` giữ cổng và cả chuỗi Nginx tới backend hoạt động |

## 11. Kiến thức mở rộng

**`0.0.0.0` và `127.0.0.1`.**

| Địa chỉ bind | Ý nghĩa | Ví dụ trong bài |
|---|---|---|
| `0.0.0.0:8082` | mọi giao diện IPv4, truy cập được từ bên ngoài nếu firewall cho phép | `python3 -m http.server` (có thể giới hạn bằng `--bind 127.0.0.1`) |
| `127.0.0.1:8082` | chỉ loopback, chỉ máy này truy cập được | Spring Boot (`server.address=127.0.0.1`), chỉ Nginx gọi vào |

Cổng được tính theo cặp (địa chỉ, cổng), nhưng wildcard `0.0.0.0` bao trùm mọi địa chỉ nên xung đột với bất kỳ địa chỉ cụ thể nào cùng cổng. Do đó Java bind `127.0.0.1` vẫn lỗi khi Python giữ `0.0.0.0:8082`. Tiến trình giả lập bind mọi địa chỉ còn làm lộ cổng 8082 ra ngoài, một lý do nữa để không chạy thử nghiệm trên cổng dịch vụ.

**`TIME_WAIT` và `SO_REUSEADDR`.** Khi một kết nối TCP đóng, phía đóng trước giữ socket ở trạng thái `TIME_WAIT` khoảng 60 giây. Socket này không còn là `LISTEN` nên không chặn bind nếu tiến trình mới đặt `SO_REUSEADDR` (Tomcat và `http.server` đều đặt). Vì vậy `Address already in use` do `TIME_WAIT` hiếm gặp với dịch vụ web. `SO_REUSEADDR` không cho bind chồng lên một socket đang `LISTEN`, nên nó không giải quyết được sự cố trong bài này. Kiểm tra bằng `ss -tan state time-wait '( sport = :8082 )'`.

**Phòng ngừa.**

- Không chạy thử nghiệm trên cổng của dịch vụ thật; dùng cổng khác (ví dụ 18082) cho việc test, ví dụ `python3 -m http.server 18082 --bind 127.0.0.1`.
- Đưa mọi tiến trình dài hạn vào systemd để có chủ sở hữu rõ ràng, log tập trung và dừng/chạy bằng một lệnh.
- Ghi quy ước cổng vào tài liệu (8082: backend Spring Boot, 80: Nginx, 2222: SSH) và kiểm tra bằng `ss -tlnp` trước khi triển khai.
- Dọn tiến trình nền sau khi test bằng `jobs -l` và `kill %1`.

**Đổi cổng Spring Boot** khi không thể giải phóng cổng 8082 (nhớ sửa cả `proxy_pass` trong Nginx cho khớp):

```text
java -jar /opt/spring-app/app.jar --server.port=8083     # đối số dòng lệnh
SERVER_PORT=8083 java -jar /opt/spring-app/app.jar       # biến môi trường
server.port=8083                                         # trong application.properties
```

Với systemd, sửa dòng `ExecStart` rồi chạy `sudo systemctl daemon-reload` và `sudo systemctl restart spring-app.service`.

## 12. Bảng xử lý sự cố

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| `Port 8082 was already in use` / `Address already in use` | Có tiến trình khác đang `LISTEN` cổng đó | `sudo ss -tlnp \| grep 8082`, xem `ps`, rồi `kill` |
| `ss -tlnp` không hiện cột tiến trình | Chạy không có `sudo` với tiến trình của user khác | Chạy lại bằng `sudo` |
| `kill <PID>` xong tiến trình vẫn còn | Bỏ qua SIGTERM hoặc đang kẹt | Chờ vài giây, kiểm tra `ps -p`, sau đó `kill -9 <PID>` |
| Vừa kill xong tiến trình xuất hiện lại với PID mới | Được systemd hoặc trình giám sát khác khởi động lại (`Restart=`) | `sudo systemctl stop <dịch vụ>` (và `disable` nếu cần), không dùng `kill` |
| Dịch vụ `failed`, `start-limit-hit` | Quá 5 lần khởi động trong 300 giây | Giải phóng cổng, `sudo systemctl reset-failed <dịch vụ>`, rồi `restart` |
| Dịch vụ cứ `activating (auto-restart)` | Thoát lỗi liên tục, chờ `RestartSec` | `systemctl stop` để dừng vòng lặp, đọc `journalctl -u`, sửa nguyên nhân |
| `netstat: command not found` | Chưa cài `net-tools` | Dùng `ss`, hoặc `sudo apt install net-tools` |
| Nginx 502 | Backend không chạy hoặc không lắng nghe | `systemctl status`, `ss -tlnp \| grep 8082` |
| Nginx 404 lạ khi backend chưa chạy | Tiến trình khác chiếm cổng backend và trả lời thay | `curl -I http://127.0.0.1:8082/` xem header `Server`, tìm PID |
| Cổng vẫn bị giữ sau khi kill | Còn tiến trình con hoặc có nhiều PID | `sudo ss -tlnp` lại, `sudo lsof -t -i :8082` liệt kê đủ PID |

## 13. Đối chiếu yêu cầu đề bài

| Yêu cầu | Thực hiện | Mục |
|---|---|---|
| Giả lập cổng 8082 bị chiếm bằng `python3 -m http.server 8082 > /dev/null 2>&1 &` | PID 24102, bind `0.0.0.0:8082` | 3 |
| Tái hiện lỗi `Address already in use` khi deploy | `systemctl start` và log `APPLICATION FAILED TO START` | 4 |
| Dùng `ss`, `netstat` hoặc `lsof` tìm PID chiếm cổng 8082 | `ss`, `lsof`, `fuser` cùng ra PID 24102; `netstat` chưa cài | 5 |
| Ghi PID và thông tin tiến trình vào `troubleshoot_report.md` | Bảng thông tin tiến trình, `ps`, `/proc` | 6 |
| Dùng `kill` (hoặc `kill -9` nếu cần) kết thúc tiến trình an toàn | `kill 24102` (SIGTERM) đủ, không cần `kill -9`; đã nêu khi nào cần | 7 |
| Khởi động lại `spring-app.service` | `reset-failed` và `restart`, `active (running)`, PID 24250 | 8 |
| Xác nhận cổng 8082 do `java` (`app.jar`) quản lý | `sudo ss -tlnp \| grep 8082` và `sudo lsof -i :8082` đều ra `java` | 9 |
| Nộp `troubleshoot_report.md` có chuỗi lệnh và giải trình | Toàn bộ lệnh theo thứ tự cùng quy trình 6 bước | 2 đến 10 |

## 14. Kết luận

Xung đột cổng được xử lý theo quy trình có kiểm chứng ở từng bước: đọc log để xác định đúng nguyên nhân, dùng ba công cụ độc lập để tìm PID 24102, xác nhận chủ sở hữu và nguồn gốc tiến trình bằng `ps` và `/proc`, tắt bằng SIGTERM thay vì `kill -9`, rồi khôi phục `spring-app.service` và kiểm tra bằng `ss`, `lsof`, `curl`. Cuối phiên, cổng 8082 do `java` PID 24250 giữ, endpoint `/health` trả `UP` và Nginx trả 200.

Bài học chính: không thử nghiệm trên cổng của dịch vụ thật; luôn nhận diện chủ sở hữu tiến trình trước khi tắt; dừng vòng lặp khởi động lại trước khi chẩn đoán; dùng `kill` rồi mới `kill -9`; sau khi dịch vụ thất bại liên tiếp thì `reset-failed` trước khi chạy lại.

Các file nộp trong `homework/session_07/ex5/`: `troubleshoot_report.md` (báo cáo này), `terminal_log.txt` (log toàn phiên), `free_port.sh` (script giải phóng cổng: `sudo ./free_port.sh [--yes] [--timeout GIÂY] CỔNG`) và `README.md`.
