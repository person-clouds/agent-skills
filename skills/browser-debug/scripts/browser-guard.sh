#!/usr/bin/env bash
# browser-guard.sh —— 清理 DSH 临时无头 Chromium 的守卫
#
# 只匹配同时满足以下条件的进程，避免误杀用户日常浏览器：
#   1. comm 为 chrome / chromium；
#   2. 命令行包含 --headless；
#   3. 命令行包含 Playwright 缓存路径、dsh-chrome 临时 profile 或 --remote-debugging-port。
#
# 默认 --dry-run 只打印；systemd timer 使用 --apply 真正清理。
# 可调环境变量：
#   BROWSER_GUARD_MIN_AGE  默认 300 秒
#   BROWSER_GUARD_CPU      默认 300（3 核）
#   BROWSER_GUARD_SAMPLE   默认 2 秒
#   BROWSER_GUARD_LOG_DIR  默认 ~/.dsh/state/browser-guard

set -euo pipefail

MODE="dry-run"
case "${1:-}" in
    --apply) MODE="apply" ;;
    --dry-run|"") MODE="dry-run" ;;
    -h|--help)
        sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *) echo "未知参数：$1（支持 --dry-run / --apply）" >&2; exit 64 ;;
esac

MIN_AGE="${BROWSER_GUARD_MIN_AGE:-300}"
CPU_LIMIT="${BROWSER_GUARD_CPU:-300}"
SAMPLE="${BROWSER_GUARD_SAMPLE:-2}"
LOG_DIR="${BROWSER_GUARD_LOG_DIR:-$HOME/.dsh/state/browser-guard}"
LOG_FILE=""

[[ "$MIN_AGE" =~ ^[0-9]+$ ]] || { echo "BROWSER_GUARD_MIN_AGE 非法" >&2; exit 64; }
[[ "$CPU_LIMIT" =~ ^[0-9]+$ ]] || { echo "BROWSER_GUARD_CPU 非法" >&2; exit 64; }
[[ "$SAMPLE" =~ ^[0-9]+$ ]] && (( SAMPLE > 0 )) || { echo "BROWSER_GUARD_SAMPLE 非法" >&2; exit 64; }

if [[ "$MODE" == "apply" ]]; then
    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        LOG_FILE="$LOG_DIR/guard.log"
    else
        echo "警告：$LOG_DIR 不可写，只写 journal" >&2
    fi
fi

log() {
    local line
    line="$(date '+%F %T') $*"
    printf '%s\n' "$line"
    [[ -n "$LOG_FILE" ]] && printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
}

is_candidate() {
    local pid="$1" comm cmdline
    comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    case "$comm" in chrome|chromium) ;; *) return 1 ;; esac
    cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
    [[ "$cmdline" == *"--headless"* ]] || return 1
    [[ "$cmdline" == *"ms-playwright"* || "$cmdline" == *"dsh-chrome"* || "$cmdline" == *"--remote-debugging-port"* ]] || return 1
    return 0
}

# 输出 "pid ticks"；只包含临时 Chromium 根进程/子进程。
snapshot() {
    local pid pids line rest u s
    if command -v pgrep >/dev/null 2>&1; then
        pids="$( { pgrep -x chrome 2>/dev/null || true; pgrep -x chromium 2>/dev/null || true; } | sort -u)"
    else
        pids=""
        for f in /proc/[0-9]*/stat; do
            pids+=" ${f#/proc/}"
        done
        pids="$(printf '%s\n' $pids | sed 's|/stat||')"
    fi
    for pid in $pids; do
        [[ -r "/proc/$pid/stat" ]] || continue
        is_candidate "$pid" || continue
        IFS= read -r line < "/proc/$pid/stat" 2>/dev/null || continue
        rest="${line#*) }"
        read -r _ _ _ _ _ _ _ _ _ _ _ u s _ <<< "$rest"
        [[ "$u" =~ ^[0-9]+$ && "$s" =~ ^[0-9]+$ ]] || continue
        printf '%s %s\n' "$pid" "$((u + s))"
    done
}

# 递归收集子孙 PID（只用于杀目标浏览器进程树，不按进程组误伤 shell）。
descendants() {
    local parent="$1" f pid line rest state ppid
    for f in /proc/[0-9]*/stat; do
        [[ -r "$f" ]] || continue
        pid="${f#/proc/}"; pid="${pid%/stat}"
        IFS= read -r line < "$f" 2>/dev/null || continue
        rest="${line#*) }"
        read -r state ppid _ <<< "$rest"
        if [[ "$ppid" == "$parent" ]]; then
            printf '%s\n' "$pid"
            descendants "$pid"
        fi
    done
}

before="$(snapshot)"
sleep "$SAMPLE"
after="$(snapshot)"
[[ -n "$before" && -n "$after" ]] || { log "未发现临时 Chromium"; exit 0; }

btime="$(awk '/^btime/{print $2}' /proc/stat 2>/dev/null || echo 0)"
hz="$(getconf CLK_TCK 2>/dev/null || echo 100)"
now="$(date +%s)"

hog_lines="$(
    awk -v sample="$SAMPLE" '
        NR == FNR { old[$1] = $2; next }
        ($1 in old) {
            d = $2 - old[$1]
            if (d > 0) printf "%.1f %s\n", d / sample, $1
        }
    ' <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sort -rn
)"
[[ -n "$hog_lines" ]] || { log "未发现临时 Chromium"; exit 0; }

found=0
while read -r cpu pid; do
    [[ -n "$pid" ]] || continue
    awk -v v="$cpu" -v t="$CPU_LIMIT" 'BEGIN{exit !(v >= t)}' || continue
    line="$(cat "/proc/$pid/stat" 2>/dev/null || true)"
    start_ticks="$(awk '{print $20}' <<< "${line#*) }" 2>/dev/null || true)"
    [[ "$start_ticks" =~ ^[0-9]+$ && "$btime" =~ ^[0-9]+$ && "$hz" =~ ^[0-9]+$ ]] || continue
    age=$(( now - btime - start_ticks / hz ))
    (( age >= MIN_AGE )) || continue

    found=1
    cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-240)"
    if [[ "$MODE" == "dry-run" ]]; then
        log "[dry-run] 将清理 PID=$pid CPU=${cpu}% AGE=${age}s CMD=$cmdline"
        continue
    fi
    mapfile -t targets < <(descendants "$pid")
    targets+=("$pid")
    log "清理 PID=$pid CPU=${cpu}% AGE=${age}s 进程树=${targets[*]} CMD=$cmdline"
    kill -TERM "${targets[@]}" 2>/dev/null || true
    for _ in $(seq 1 30); do
        alive=0
        for t in "${targets[@]}"; do kill -0 "$t" 2>/dev/null && alive=1; done
        (( alive == 0 )) && break
        sleep 0.1
    done
    kill -KILL "${targets[@]}" 2>/dev/null || true
done <<< "$hog_lines"

(( found == 0 )) && log "未发现达到阈值的临时 Chromium"
exit 0
