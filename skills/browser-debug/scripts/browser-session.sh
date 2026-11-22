#!/usr/bin/env bash
# browser-session.sh —— DSH Agent 临时无头 Chromium 统一入口
#
# 目标：任何临时浏览器调试都必须：
#   1. 用临时 profile，不污染用户浏览器数据；
#   2. 有硬超时，命令结束/超时/中断时自动清理浏览器进程组；
#   3. 可用时套 systemd user scope，限制 CPU 与内存；
#   4. 禁止调用方使用 nohup ... & 让浏览器脱离生命周期。
#
# 用法：
#   browser-session.sh [选项] -- <需要浏览器在后台运行的命令...>
#
# 示例：
#   browser-session.sh --timeout 60 -- node /tmp/cdp-check.mjs
#   browser-session.sh --url http://127.0.0.1:<端口> -- bash -c 'curl -s "$CHROME_CDP_URL/json/version"'
#
# 传给被执行的命令：
#   CHROME_BIN       Chromium 可执行文件路径
#   CHROME_CDP_URL   CDP HTTP 地址，例如 http://127.0.0.1:9223
#
# 选项：
#   --timeout N      浏览器会话最长秒数，默认 120
#   --port N         CDP 调试端口，默认 9223
#   --url URL        启动后打开的页面，默认 about:blank
#   --cpu-quota PCT  systemd scope CPU 配额，默认 200%
#   --memory-max M   systemd scope 内存上限，默认 2G
#   --keep-profile   保留临时 profile（仅排障时使用）
#   -h, --help       显示帮助

set -euo pipefail

TIMEOUT=120
PORT="${CDP_PORT:-9223}"
URL="about:blank"
CPU_QUOTA="${BROWSER_CPU_QUOTA:-200%}"
MEMORY_MAX="${BROWSER_MEMORY_MAX:-2G}"
KEEP_PROFILE=0
COMMAND=()

usage() {
    sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() { echo "错误：$*" >&2; exit 64; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)       [[ $# -ge 2 ]] || die "--timeout 缺少参数"; TIMEOUT="$2"; shift 2 ;;
        --port)          [[ $# -ge 2 ]] || die "--port 缺少参数"; PORT="$2"; shift 2 ;;
        --url)           [[ $# -ge 2 ]] || die "--url 缺少参数"; URL="$2"; shift 2 ;;
        --cpu-quota)     [[ $# -ge 2 ]] || die "--cpu-quota 缺少参数"; CPU_QUOTA="$2"; shift 2 ;;
        --memory-max)    [[ $# -ge 2 ]] || die "--memory-max 缺少参数"; MEMORY_MAX="$2"; shift 2 ;;
        --keep-profile)  KEEP_PROFILE=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        --)              shift; COMMAND=("$@"); break ;;
        *)               die "未知参数：$1（必须用 -- 分隔浏览器参数与调试命令）" ;;
    esac
done

[[ "${TIMEOUT}" =~ ^[0-9]+$ ]] && (( TIMEOUT > 0 )) || die "--timeout 必须是正整数"
[[ "${PORT}" =~ ^[0-9]+$ ]] && (( PORT > 0 && PORT < 65536 )) || die "--port 非法"
[[ ${#COMMAND[@]} -gt 0 ]] || die "缺少要执行的调试命令，请使用 -- <command...>"

find_chrome() {
    if [[ -n "${DSH_CHROME_BIN:-}" ]]; then
        printf '%s\n' "$DSH_CHROME_BIN"
        return 0
    fi
    local p
    p="$(find "$HOME/.cache/ms-playwright" -maxdepth 3 -type f -path '*/chrome-linux/chrome' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -1 | cut -d' ' -f2- || true)"
    [[ -n "$p" ]] && printf '%s\n' "$p"
}

CHROME="$(find_chrome || true)"
[[ -n "$CHROME" && -x "$CHROME" ]] || die "找不到 Playwright Chromium；请设置 DSH_CHROME_BIN 或先安装 Playwright 浏览器"

PROFILE="$(mktemp -d "${TMPDIR:-/tmp}/dsh-chrome.XXXXXX")"
UNIT=""
CHROME_PID=""
CLEANED=0

cleanup() {
    local rc=$?
    trap - EXIT INT TERM
    (( CLEANED == 1 )) && exit "$rc"
    CLEANED=1
    if [[ -n "$UNIT" ]]; then
        systemctl --user stop "$UNIT" >/dev/null 2>&1 || true
    fi
    if [[ -n "$CHROME_PID" ]]; then
        kill -TERM -- "-$CHROME_PID" 2>/dev/null || true
        for _ in $(seq 1 30); do
            kill -0 "$CHROME_PID" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL -- "-$CHROME_PID" 2>/dev/null || true
        wait "$CHROME_PID" 2>/dev/null || true
    fi
    if (( KEEP_PROFILE == 1 )); then
        echo "临时 profile 已保留：$PROFILE" >&2
    else
        rm -rf "$PROFILE"
    fi
    exit "$rc"
}
trap cleanup EXIT INT TERM

CHROME_ARGS=(
    --headless=new
    --no-sandbox
    --disable-gpu
    --disable-software-rasterizer
    --disable-dev-shm-usage
    --remote-debugging-port="$PORT"
    --user-data-dir="$PROFILE"
    "$URL"
)

# 优先放进 systemd user scope，给失控进程一个硬性 CPU/内存上限。
# DSH 沙箱内通常连不上用户总线，此时降级为 setsid 进程组 + 外层 trap 清理。
if systemctl --user show-environment >/dev/null 2>&1; then
    UNIT="dsh-browser-$$-${RANDOM}.scope"
    systemd-run --user --scope --collect --unit="$UNIT" \
        -p "CPUQuota=${CPU_QUOTA}" -p "MemoryMax=${MEMORY_MAX}" \
        -- "$CHROME" "${CHROME_ARGS[@]}" &
else
    setsid "$CHROME" "${CHROME_ARGS[@]}" &
fi
CHROME_PID=$!

# 等待 CDP 就绪，避免调试命令抢跑。
cdp_ready=0
for _ in $(seq 1 150); do
    if ! kill -0 "$CHROME_PID" 2>/dev/null; then
        echo "错误：Chromium 提前退出" >&2
        exit 1
    fi
    if curl -fsS --max-time 0.5 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
        cdp_ready=1
        break
    fi
    sleep 0.1
done
if (( cdp_ready == 0 )); then
    echo "错误：Chromium CDP 端口 ${PORT} 在 15 秒内未就绪" >&2
    exit 1
fi

export CHROME_BIN="$CHROME"
export CHROME_CDP_URL="http://127.0.0.1:${PORT}"

set +e
timeout --signal=TERM --kill-after=5s "$TIMEOUT" "${COMMAND[@]}"
rc=$?
set -e
exit "$rc"
