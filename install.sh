#!/usr/bin/env bash
# 安装本仓技能到指定 agent 的 skill 目录（默认 DSH，软链）。
#
#   ./install.sh                          # 全部技能 -> ~/.dsh/skills（软链）
#   ./install.sh change-verify            # 只装一个
#   ./install.sh --target agents          # -> ~/.agents/skills
#   ./install.sh --target workbuddy       # -> ~/.workbuddy/skills
#   ./install.sh --target claude --copy   # -> ~/.claude/skills（复制）
#   ./install.sh --project /path/to/repo  # -> <repo>/.dsh/skills（项目级）
#
# 目标目录已有同名技能时，先备份到 ~/.local/share/agent-skills-backup/<时间戳>/，
# 再替换；默认软链，仓库更新即生效。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="dsh"
PROJECT=""
MODE="link"
SKILLS=()

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="${2:?缺少 target}"; shift 2 ;;
        --project) PROJECT="${2:?缺少目录}"; shift 2 ;;
        --copy) MODE="copy"; shift ;;
        --link) MODE="link"; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "未知选项：$1" >&2; usage >&2; exit 2 ;;
        *) SKILLS+=("$1"); shift ;;
    esac
done

case "$TARGET" in
    dsh)      USER_DIR="$HOME/.dsh/skills";        PROJECT_SUBDIR=".dsh/skills" ;;
    agents)   USER_DIR="$HOME/.agents/skills";     PROJECT_SUBDIR=".agents/skills" ;;
    claude)   USER_DIR="$HOME/.claude/skills";     PROJECT_SUBDIR=".claude/skills" ;;
    workbuddy) USER_DIR="$HOME/.workbuddy/skills"; PROJECT_SUBDIR="" ;;
    *) echo "未知 target：$TARGET（可选 dsh|agents|claude|workbuddy）" >&2; exit 2 ;;
esac

if [[ -n "$PROJECT" ]]; then
    [[ -n "$PROJECT_SUBDIR" ]] || { echo "workbuddy 只支持用户级安装，不能配 --project" >&2; exit 2; }
    [[ -d "$PROJECT" ]] || { echo "项目目录不存在：$PROJECT" >&2; exit 2; }
    DEST_DIR="$PROJECT/$PROJECT_SUBDIR"
else
    DEST_DIR="$USER_DIR"
fi

mapfile -t ALL < <(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
[[ ${#ALL[@]} -gt 0 ]] || { echo "仓内没有 skills/*" >&2; exit 1; }

if [[ ${#SKILLS[@]} -eq 0 ]]; then
    SKILLS=("${ALL[@]}")
fi

FAILED=0
for name in "${SKILLS[@]}"; do
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ && "$name" != "." && "$name" != ".." ]] \
        || { echo "非法技能名：$name" >&2; FAILED=1; continue; }
    src="$ROOT/skills/$name"
    [[ -f "$src/SKILL.md" ]] || { echo "跳过：skills/$name 缺少 SKILL.md" >&2; FAILED=1; continue; }
    dest="$DEST_DIR/$name"
    mkdir -p "$DEST_DIR"
    if [[ -e "$dest" || -L "$dest" ]]; then
        if [[ "$MODE" == "link" && -L "$dest" && "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
            echo "已是最新：$dest"
            continue
        fi
        backup="$(mktemp -d "$HOME/.local/share/agent-skills-backup/$(date +%Y%m%d-%H%M%S).XXXXXX")"
        mv "$dest" "$backup/$name"
        echo "已备份旧版本：$backup/$name"
    fi
    # 先装到临时名再替换，避免中途失败把已有 skill 留成空目录。
    tmp="$DEST_DIR/.$name.tmp.$$"
    rm -rf -- "$tmp"
    if [[ "$MODE" == "copy" ]]; then
        cp -a "$src" "$tmp"
    else
        ln -sfn "$src" "$tmp"
    fi
    mv -T -- "$tmp" "$dest" || { rm -rf -- "$tmp"; echo "安装失败：$name" >&2; FAILED=1; continue; }
    echo "已安装 $name -> $dest（$MODE）"
done
exit "$FAILED"
