# agent-skills

跨平台 Agent Skills 合集：一个技能一份 `SKILL.md`，装到 DSH、Codex/`.agents`、Claude、WorkBuddy 都能用。

给谁用：在多个 agent 平台上复用同一套工作规范的人。这里只放**与具体产品无关**的通用工作流技能；产品能力技能仍随各自产品仓发布。

## 先说最要紧的

- 两个内核技能：`browser-debug`（临时无头 Chromium）、`doc-slim`（文档精简）。
- `change-verify`（交付前核验）已迁入 `dsh-workflow-shortcuts` 作为内置技能，本仓不再保留副本；非 DSH 平台需要时从该仓复制 `skills/change-verify/`。
- `./install.sh` 默认软链到 `~/.dsh/skills`，仓库更新即生效；替换前自动备份。
- 支持 `--target dsh|agents|claude|workbuddy`、`--project <repo>`、`--copy`。
- 技能正文已脱敏：不含本机绝对路径、个人目录、内网地址；路径用「本技能目录 / 工作区根」表达。
- 与产品仓技能不重复：`dsh-local-vision` 等技能仍在各自仓库，本仓只收录通用工作流。

## 安装

```bash
git clone https://github.com/person-clouds/agent-skills.git
cd agent-skills

./install.sh                       # 全部 -> ~/.dsh/skills（软链）
./install.sh browser-debug         # 只装一个
./install.sh --target agents       # Codex 等扫描 ~/.agents/skills 的平台
./install.sh --target workbuddy    # WorkBuddy 用户级（不支持 --project）
./install.sh --target claude --copy
./install.sh --project ~/my-repo   # 项目级 <repo>/.dsh/skills
```

其它平台：把 `skills/<name>/` 整个复制到该平台扫描的 skills 目录即可；`SKILL.md` 的 `name` 必须与目录名一致。

## 目录结构

```text
skills/
├── browser-debug/          SKILL.md + scripts/ + systemd/ + install-guard.sh
└── doc-slim/SKILL.md
install.sh
```

## 收录标准

- 与具体产品解耦，换工作区、换平台仍成立；依赖本机工具时在技能里写明降级路径。
- 正文只写可执行步骤与判定证据，不写个人环境、绝对路径、token、内网地址。
- 一个技能一个目录，目录名 = frontmatter `name`；改语义要单独提交并说明影响面。

## 与产品仓技能的区别

`dsh-local-vision`、`free-ai-router`、`workdir-rag`、`dsh-superagent` 等技能随各自产品仓发布，不复制到这里；本仓只收录跨产品通用的工作流技能。

`change-verify` 依赖 `dsh-context-guard` 的核验态（标题 `V：`/`TODO：V：`）与 `/V` 入口，属于 DSH 产品能力，随 `dsh-workflow-shortcuts` ≥ `0.4.0` 发布并从 `ctx.inject(['skills'])` 注册。

## 回滚

```bash
ls ~/.local/share/agent-skills-backup/          # 找到替换前的旧版本
rm ~/.dsh/skills/<name>
cp -a ~/.local/share/agent-skills-backup/<时间戳>/<name> ~/.dsh/skills/
```

## License

MIT
