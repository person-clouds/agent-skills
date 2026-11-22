#!/usr/bin/env bash
# ============================================================================
# install-guard.sh —— 安装/卸载 DSH 临时 Chromium 清理守卫（用户级 systemd）
#
# 必须在用户自己的图形/登录终端执行，或由宿主侧代执行：
#   bash install-guard.sh install     # 在本技能目录内执行
#   bash install-guard.sh status
#   bash install-guard.sh uninstall
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE="dsh-browser-guard.service"
TIMER="dsh-browser-guard.timer"

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

need_user_bus() {
    if ! systemctl --user show-environment >/dev/null 2>&1; then
        echo "错误：连不上用户级 systemd 总线。请在用户登录终端执行。" >&2
        exit 1
    fi
}

do_install() {
    need_user_bus
    mkdir -p "$UNIT_DIR"
    # 路径里可能有 & | \，替换前先转义，避免把 unit 写坏。
    here_esc="${HERE//\\/\\\\}"
    here_esc="${here_esc//&/\\&}"
    here_esc="${here_esc//|/\\|}"
    sed "s|@HERE@|$here_esc|g" "$HERE/systemd/$SERVICE" > "$UNIT_DIR/$SERVICE"
    sed "s|@HERE@|$here_esc|g" "$HERE/systemd/$TIMER" > "$UNIT_DIR/$TIMER"
    chmod 644 "$UNIT_DIR/$SERVICE" "$UNIT_DIR/$TIMER"
    systemctl --user daemon-reload
    systemctl --user enable --now "$TIMER"
    echo "已安装：$SERVICE / $TIMER（每分钟检查一次，日志进 journal）"
    systemctl --user list-timers "$TIMER" --no-pager || true
}

do_uninstall() {
    need_user_bus
    systemctl --user disable --now "$TIMER" 2>/dev/null || true
    rm -f "$UNIT_DIR/$SERVICE" "$UNIT_DIR/$TIMER"
    systemctl --user daemon-reload
    echo "已卸载 $SERVICE / $TIMER"
}

do_status() {
    need_user_bus
    systemctl --user status "$TIMER" --no-pager || true
    systemctl --user list-timers "$TIMER" --no-pager || true
    journalctl --user -u "$SERVICE" -n 20 --no-pager || true
}

case "${1:-install}" in
    install) do_install ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    -h|--help) usage ;;
    *) echo "未知子命令：$1" >&2; usage; exit 2 ;;
esac
