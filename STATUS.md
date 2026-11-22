# STATUS

> 最后核对：2026-11-22

| 项 | 状态 |
|---|---|
| 仓库 | `person-clouds/agent-skills`，public，默认分支 `main` |
| 版本 | 0.1.0（首版，无 npm 包） |
| 技能 | `change-verify` / `browser-debug` / `doc-slim` |
| 安装 | `./install.sh`：dsh / agents / claude / workbuddy，默认软链，可 `--copy`、`--project` |
| 脱敏 | 已去除本机绝对路径、个人标识、内网地址 |
| 验证 | `bash -n install.sh`；三技能在本机 DSH 加载正常 |
| 已知限制 | WorkBuddy 仅用户级；项目级安装要求该平台扫描对应目录 |
