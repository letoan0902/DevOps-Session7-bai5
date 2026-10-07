#!/usr/bin/env bash
# free_port.sh - Giải phóng một cổng TCP đang bị tiến trình khác chiếm giữ (Session 07 - Bài 5).
#
# Quy trình của script (tương ứng các bước chẩn đoán trong troubleshoot_report.md):
#   1. Tìm PID đang LISTEN trên cổng bằng ss (nếu không có ss thì dùng lsof).
#   2. Liệt kê thông tin từng tiến trình: PID, user, thời gian chạy, dòng lệnh.
#   3. Hỏi xác nhận (bỏ qua nếu có --yes), rồi gửi SIGTERM để tiến trình tự dọn dẹp.
#   4. Chờ tối đa TIMEOUT giây; tiến trình nào còn sống thì mới gửi SIGKILL.
#   5. Kiểm tra lại cổng đã trống hay chưa.
#
# Cách dùng:
#   sudo ./free_port.sh [--yes] [--timeout GIÂY] CỔNG
#   Ví dụ: sudo ./free_port.sh 8082
#          sudo ./free_port.sh --yes --timeout 5 8082
#
# Mã thoát: 0 = cổng đã trống; 1 = cổng vẫn bị chiếm hoặc người dùng từ chối; 2 = sai tham số.
# Lưu ý: nên chạy bằng sudo, nếu không ss/lsof không thấy tiến trình của user khác
# và lệnh kill sẽ bị từ chối (Operation not permitted).

set -euo pipefail

TIMEOUT=10     # số giây chờ sau SIGTERM trước khi dùng SIGKILL
ASSUME_YES=0   # 1 = không hỏi xác nhận
PORT=""

usage() {
    cat <<'EOF'
Cách dùng: free_port.sh [--yes] [--timeout GIÂY] CỔNG

  CỔNG              số cổng TCP cần giải phóng (1-65535)
  -y, --yes         không hỏi xác nhận, gửi tín hiệu ngay
  -t, --timeout N   số giây chờ sau SIGTERM trước khi SIGKILL (mặc định 10)
  -h, --help        hiển thị trợ giúp này
EOF
}

die() {
    echo "LOI: $1" >&2
    exit 2
}

# ---------------------------------------------------------------------------
# Đọc tham số dòng lệnh
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        -t|--timeout)
            [[ $# -ge 2 ]] || die "thiếu giá trị cho $1"
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            usage >&2
            die "tùy chọn không hợp lệ: $1"
            ;;
        *)
            [[ -z "$PORT" ]] || die "chỉ nhận một số cổng"
            PORT="$1"
            shift
            ;;
    esac
done

[[ -n "$PORT" ]] || { usage >&2; die "chưa nhập số cổng"; }
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die "cổng không hợp lệ: $PORT"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "timeout phải là số nguyên không âm: $TIMEOUT"

# ---------------------------------------------------------------------------
# Hàm tiện ích
# ---------------------------------------------------------------------------

# In ra danh sách PID đang LISTEN trên $PORT (mỗi PID một dòng, không trùng lặp).
# Cuối pipeline có "|| true" vì grep trả mã 1 khi không có kết quả, mà script đang bật pipefail.
find_pids() {
    if command -v ss >/dev/null 2>&1; then
        ss -H -tlnp "sport = :${PORT}" 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -un || true
    elif command -v lsof >/dev/null 2>&1; then
        lsof -t -nP -iTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null | sort -un || true
    else
        die "cần cài ss (iproute2) hoặc lsof để tìm tiến trình"
    fi
}

# Kiểm tra PID còn tồn tại hay không.
is_alive() {
    kill -0 "$1" 2>/dev/null
}

# In thông tin một tiến trình và cảnh báo nếu nó do systemd quản lý.
describe_pid() {
    local pid="$1" unit=""
    ps -o pid=,user=,etime=,args= -p "$pid" || true
    if [[ -r "/proc/${pid}/cgroup" ]]; then
        unit="$(grep -o '[^/]*\.service' "/proc/${pid}/cgroup" 2>/dev/null | tail -n 1 || true)"
    fi
    if [[ -n "$unit" ]]; then
        echo "      CANH BAO: tiến trình thuộc ${unit}; nếu có Restart= thì systemd sẽ chạy lại." >&2
        echo "      Nên dùng: sudo systemctl stop ${unit}" >&2
    fi
}

# ---------------------------------------------------------------------------
# Bước 1 và 2: tìm và liệt kê tiến trình chiếm cổng
# ---------------------------------------------------------------------------
mapfile -t PIDS < <(find_pids)

if [[ ${#PIDS[@]} -eq 0 ]]; then
    echo "Cổng ${PORT} đang trống, không cần xử lý."
    exit 0
fi

echo "Các tiến trình đang lắng nghe trên cổng ${PORT}:"
echo "      PID USER           ELAPSED COMMAND"
for pid in "${PIDS[@]}"; do
    describe_pid "$pid"
done

# ---------------------------------------------------------------------------
# Bước 3: xác nhận
# ---------------------------------------------------------------------------
if [[ "$ASSUME_YES" -ne 1 ]]; then
    if [[ ! -t 0 ]]; then
        echo "Không có terminal để hỏi xác nhận; dùng --yes nếu muốn chạy tự động." >&2
        exit 1
    fi
    read -r -p "Gửi SIGTERM tới các tiến trình trên? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Đã hủy, không có tiến trình nào bị tắt."; exit 1 ;;
    esac
fi

# ---------------------------------------------------------------------------
# Bước 4: SIGTERM, chờ, rồi SIGKILL nếu cần
# ---------------------------------------------------------------------------
for pid in "${PIDS[@]}"; do
    echo "Gửi SIGTERM tới PID ${pid}"
    kill -TERM "$pid" 2>/dev/null || echo "  Không gửi được tín hiệu tới ${pid} (đã thoát hoặc thiếu quyền)." >&2
done

waited=0
while (( waited < TIMEOUT )); do
    remaining=0
    for pid in "${PIDS[@]}"; do
        if is_alive "$pid"; then
            remaining=$((remaining + 1))
        fi
    done
    [[ "$remaining" -eq 0 ]] && break
    sleep 1
    waited=$((waited + 1))
done

for pid in "${PIDS[@]}"; do
    if is_alive "$pid"; then
        echo "PID ${pid} chưa thoát sau ${TIMEOUT} giây, gửi SIGKILL"
        kill -KILL "$pid" 2>/dev/null || echo "  Không gửi được SIGKILL tới ${pid}." >&2
    fi
done

# Cho kernel một khoảng ngắn để đóng socket trước khi kiểm tra lại.
sleep 1

# ---------------------------------------------------------------------------
# Bước 5: xác minh cổng đã được giải phóng
# ---------------------------------------------------------------------------
mapfile -t LEFT < <(find_pids)
if [[ ${#LEFT[@]} -eq 0 ]]; then
    echo "Cổng ${PORT} đã được giải phóng."
    exit 0
fi

echo "Cổng ${PORT} vẫn bị chiếm bởi PID: ${LEFT[*]}" >&2
echo "Kiểm tra thêm: tiến trình có thể được systemd khởi động lại, hoặc chạy bởi user khác." >&2
exit 1
