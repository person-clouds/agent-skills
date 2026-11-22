# STATUS

> 最后核对：2026-11-22

| 项 | 状态 |
|---|---|
| 仓库 | `person-clouds/agent-skills`，public，默认分支 `main` |
| 版本 | 0.1.0（首版，无 npm 包） |
| 技能 | `browser-debug` / `doc-slim`；`change-verify` 已迁入 `dsh-workflow-shortcuts`（随插件内置发布） |
| 安装 | `./install.sh`：dsh / agents / claude / workbuddy，默认软链，可 `--copy`、`--project` |
| 脱敏 | 已去除本机绝对路径、个人标识、内网地址 |
| 核验 | 本仓不再含 `change-verify`：自 2026-11-22 起该技能由 `dsh-workflow-shortcuts` ≥ 0.4.0 内置（只读、两轮封顶、只报告不修）；本仓仅保留 README 指针，非 DSH 平台从 shortcuts 仓复制 |
| 验证 | `bash -n install.sh`；`install.sh` 按目录遍历，删除 `change-verify` 后无需改脚本；两技能在本机 DSH 加载正常 |
| 已知限制 | WorkBuddy 仅用户级；项目级安装要求该平台扫描对应目录 |
