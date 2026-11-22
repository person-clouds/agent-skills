---
name: browser-debug
description: 用临时无头 Chromium/Playwright 调试本机页面时的统一安全规范。强制使用受控包装器、临时 profile、硬超时与进程清理，避免浏览器失控吃满 CPU。
whenToUse: 需要通过 Playwright/Chromium、CDP、截图或 DOM 检查调试本机 Web 页面时；或发现残留 headless Chromium 需要排查/清理时。
---

# 临时浏览器调试规范

## 铁律

1. **禁止** `nohup chrome ... &`、`chromium ... &` 或其他让浏览器脱离当前命令生命周期的方式。
2. 临时启动 Chromium 必须用本技能的 `scripts/browser-session.sh`；它提供临时 profile、硬超时、`trap` 清理和 systemd CPU/内存限额。
3. 用 Playwright 库时，必须 `try/finally` 里 `await browser.close()`；不要只断开连接。
4. 测试/调试结束必须确认命令退出、端口关闭、无残留 `chrome-linux/chrome` 进程。

> `$SKILL_DIR` 指本技能安装目录：DSH 默认 `~/.dsh/skills/browser-debug`，工作区内为 `.dsh/skills/browser-debug`，其它平台换成实际目录。

## 用受控包装器跑 CDP 脚本

```bash
cd <你的项目目录>
bash "$SKILL_DIR/scripts/browser-session.sh" \
  --timeout 60 -- node /tmp/cdp-check.mjs
```

> 需要浏览器能力时，不要只想到 Playwright/MCP；如果当前 preset 有 `skill` 工具，先加载 `browser-debug` 技能，再按本规范选择 Playwright、CDP 或系统 Chromium。

包装器会：

- 用 `mktemp -d /tmp/dsh-chrome.XXXXXX` 建临时 profile；
- 启动 `--headless=new --no-sandbox --disable-gpu --disable-software-rasterizer`；
- 等待 CDP 就绪，向被调命令导出 `CHROME_CDP_URL` 和 `CHROME_BIN`；
- 可用时通过 `systemd-run --user --scope` 限制 `CPUQuota=200%`、`MemoryMax=2G`；
- 调试命令退出、超时、Ctrl-C 或异常时，清理整个浏览器进程树和临时 profile。

## Playwright 正确写法

```js
import { chromium } from 'playwright'

const browser = await chromium.launch({
  headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--disable-software-rasterizer'],
})
try {
  const page = await browser.newPage()
  await page.goto('http://127.0.0.1:<端口>', { waitUntil: 'domcontentloaded' })
  console.log(await page.title())
} finally {
  await browser.close()  // 必须放 finally
}
```

## 排查/清理残留

```bash
# 只预览，不杀
bash "$SKILL_DIR/scripts/browser-guard.sh" --dry-run

# 手动应用一次（只匹配临时 headless Chromium）
bash "$SKILL_DIR/scripts/browser-guard.sh" --apply

# 安装每分钟自动守卫（用户级 systemd）
bash "$SKILL_DIR/install-guard.sh" install
bash "$SKILL_DIR/install-guard.sh" status
```

守卫只清理同时满足以下条件的进程，不会误杀日常 Chrome：

- `comm` 是 `chrome` 或 `chromium`；
- 命令行包含 `--headless`；
- 命令行还包含 `ms-playwright`、`dsh-chrome` 或 `--remote-debugging-port`；
- 运行超过 5 分钟且 CPU 超过 300%。

## 历史教训

2026-11-15 09:22，一个 DSH 排障会话用 `nohup` 启动 Playwright Chromium 后未关闭，GPU 进程空转约 1400% CPU，主机 load 升到 15+。根因不是 Playwright 本身，而是临时进程没有生命周期管理。
