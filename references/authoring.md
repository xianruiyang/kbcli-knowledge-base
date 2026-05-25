# 使用 kbCli 创建知识库

当需要创建新的 KB skill、把文档处理成 KB、或追加来源时，使用此 reference。可复用/高质量 KB 还要阅读 `quality-definition.md`。

命令示例使用 `SKILL.md` 中定义的随包 Release 运行时变量 `$KbExe` 和 `$VectorExe`。

## 创建新 KB 骨架

选择稳定的小写 `kb_id`、展示名和输出目录，然后运行：

```powershell
& $KbExe init --kb-id <kb-id> --name "<display name>" --output <kb-dir> --json
```

`$KbExe init` 会创建最小 KB skill 骨架。它在结构上有效，但在添加来源、ingest、chunk、生成 mirror、构建索引并验证前，不可查询。

初始化后，检查并补齐生成的 manifest 和 skill wrapper。可用 KB skill 应保持 `SKILL.md` 紧凑，链接到任务专用 reference，并包含足够的独立指引，让 Codex 不依赖隐藏上下文也能使用 KB。

### KB skill 的 kbCli 导向要求

具体 KB skill 不携带 `kb.exe`，必须导向 `kbcli-knowledge-base` skill 中的随包 Release runtime。生成或手写 KB `SKILL.md` 时必须满足：

- 明确声明依赖 `kbcli-knowledge-base`，并说明不要使用裸 `kb`、`PATH`、registry alias 或源码 checkout Debug build 查找 CLI；
- 提供一个 runtime 解析块，先定位本 KB skill 目录，再调用 `kbcli-knowledge-base/scripts/resolve-kbcli.ps1`，得到 `$KbExe`、`$VectorExe` 和 `$Manifest`；
- 所有查询、构建、维护示例都使用 `& $KbExe ...`，禁止写 `kb search`、`kb fetch`、`kb index build` 等裸命令；
- 如果运行时不可用，才进入 standalone read-only fallback；不要把 fallback 描述成 Hybrid 或可写维护路径；
- 不复制 `kb.exe` 到每个 KB skill，不把本机绝对 runtime path 写死到 portable skill。

推荐 KB `SKILL.md` 查询块：

```powershell
$ThisSkillFile = "<loaded this KB SKILL.md full path>"
if (-not (Test-Path -LiteralPath $ThisSkillFile -PathType Leaf)) {
    $ThisSkillFile = Join-Path (Get-Location) "skills\<kb-skill-name>\SKILL.md"
}
if (-not (Test-Path -LiteralPath $ThisSkillFile -PathType Leaf) -and -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $ThisSkillFile = Join-Path $env:USERPROFILE ".codex\skills\<kb-skill-name>\SKILL.md"
}
if (-not (Test-Path -LiteralPath $ThisSkillFile -PathType Leaf)) {
    throw "KB skill path unavailable; use the loaded SKILL.md path or run from the project root."
}
$ThisSkillDir = Split-Path -Parent $ThisSkillFile
$Runtime = & (Join-Path $ThisSkillDir "scripts\resolve-kbcli-runtime.ps1") | ConvertFrom-Json
$KbExe = $Runtime.kb_exe
$VectorExe = $Runtime.vector_exe
$Manifest = $Runtime.manifest

& $KbExe search --manifest $Manifest --query "<source-language question plus exact identifiers>" --mode hybrid --top-k 8 --candidate-k 40 --json
& $KbExe fetch --manifest $Manifest --chunk-id "<chunk_id>" --include-source --include-links --json
```

`scripts/resolve-kbcli-runtime.ps1` 应优先查找 `$env:USERPROFILE\.codex\skills\kbcli-knowledge-base\SKILL.md`，再查找当前工作目录的 `skills/kbcli-knowledge-base/SKILL.md` 和与当前 KB skill 并列的 `kbcli-knowledge-base/SKILL.md`。找到后调用其 `scripts/resolve-kbcli.ps1`，并返回当前 KB 的 manifest path。这样新对话里 agent 只加载具体 KB skill，也能被导向正确 runtime。

按需检查或创建：

- `SKILL.md`：范围、检索语言、Hybrid-first 查询规则、kbCli runtime 导向、应读取的 reference；
- `scripts/resolve-kbcli-runtime.ps1`：KB-local bridge，只负责定位 `kbcli-knowledge-base` 并返回 `$KbExe`、`$VectorExe`、`manifest`；
- `agents/openai.yaml`：给 OpenAI/Codex agent 的短 prompt；
- `references/topic-map.md`：主要来源区域、术语和 source-language 线索；
- `references/standalone-guide.md`：不依赖外部对话上下文时如何使用 KB；
- `eval/smoke.jsonl`：有代表性的检索问题；高质量 KB 必须包含。

新 KB 在首次完整构建前，还要设置这些 manifest policy：

- `primary_language` 和 `source_languages`：检索应使用 KB/source language；技术标识符保持原样。
- `query_language_policy`：记录是否期望 query rewrite/translation。
- `domain` 和 `authority_policy`：记录领域和来源优先级。
- `payload_schema.required_fields` 和 `payload_schema.required_payload_indexes`：声明 `index verify` 所需的 Qdrant payload fields 和 indexes。
- `embedding_text`：声明向量化输入折叠策略。默认应把 Markdown 链接折叠为标签，裸 URL 删除，图片/视频/裸 asset path 折叠为短描述；实际 `text` 和 Markdown mirror 仍保留原链接与媒体引用。
- `publish.alias`：production-style promote/rollback 使用的稳定 Qdrant alias。

首次完整 vector build 前，至少满足以下 manifest/skill 就绪检查：

- 检索语言在 manifest 中机器可读，在 KB `SKILL.md` 中人类可读；
- domain 和 authority policy 说明哪些来源优先于其他来源；
- Qdrant indexing 前已声明用于 filter、citation 和 source reconstruction 的 payload fields；
- KB skill 要求 agent 先解析 `$KbExe`，再用 Hybrid、fetch 证据，并用用户语言回答；
- KB skill 和 guides 中不出现裸 `kb ...` 示例；
- portable package 不包含本地模型路径、provider 选择、registry 文件、Qdrant live storage 或 runtime logs。

任何有意跳过的项目或来源限制，都要记录在 runtime log 和最终交接中。

## 添加来源

使用显式 source type。当前 CLI 已覆盖 markdown、JSONL、HTML/web URL、text、PDF、DOCX 和 code adapter。

示例：

```powershell
& $KbExe source add --manifest <manifest> --type markdown --path <file-or-dir> --title "<title>" --json
& $KbExe source add --manifest <manifest> --type pdf --path <file.pdf> --title "<title>" --json
& $KbExe source add --manifest <manifest> --type web --path <url> --title "<title>" --json
```

默认保持 source path 可迁移。除非 manifest 明确启用 `root_policy.allow_external_paths`，否则将来源文档放在 KB 目录下，例如 `references/source-docs/` 或 `sources/`，并以相对路径或 KB-local 路径添加。不要把生成的 mirror、indexes、state、package 输出、runtime logs、本地模型文件或 registry 文件作为 source 添加。

如果 `source add` 前需要清理来源，例如语言过滤、UDN/HTML 转换、metadata 剥离、链接重写、图片复制或去重，清理后的 source tree 应保存在 KB 内，并在 `state/` 或项目 `runtimeLogs/` 中保留简短准备记录。记录应说明删除了什么、重写了什么、哪些 asset 未恢复，以及使用的原始 source path。不要把派生的 `content/markdown/` 输出作为清理后来源内容的唯一可读副本。

媒体资源准备遵循保守规则：只保留能帮助理解正文的图片、离线视频或其他资源；站点 UI、头像、Logo、缩略图、占位动画、小图、重复装饰图和无法提供证据价值的媒体不要进入 KB source。保留的静态图片默认转为 JPEG 并压缩；带 alpha/透明通道的源图先用白底合成再写出 JPEG。只有截图、UI 图标、线稿、代码图或透明信息在 JPEG 中明显损坏时，才例外保留 PNG，并在准备记录中说明原因。GIF 或动画资源沿用项目既有转换策略：非必要不保留；必要动画优先转为压缩 WebP 或抽取关键帧 JPEG，并在 Markdown 中链接回去或用文字说明。Markdown 正文应保留可读媒体链接、alt/caption 或有意义文件名；向量化输入仍按 `embedding_text` policy 折叠媒体和 asset path。

添加 source directory 时，排除不应成为检索证据的脚手架和生成文件：

```powershell
& $KbExe source add --manifest <manifest> --type markdown --path <kb-dir>\references\source-docs --title "<title>" --exclude README.md --exclude index.md --exclude kb-manifest.json --json
```

如果必须使用外部 source path，显式更新 manifest，记录放宽可迁移性的原因，并在打包前重新验证。

然后检查并同步 source state：

```powershell
& $KbExe source list --manifest <manifest> --json
& $KbExe source sync --manifest <manifest> --json
```

## 构建可查询资产

常规 KB 创建优先使用有记录的 pipeline：

```powershell
& $KbExe pipeline plan --manifest <manifest> --recipe local-docs --target all --json
& $KbExe pipeline run --manifest <manifest> --recipe local-docs --target all --vector-exe $VectorExe --json
```

`pipeline run` 会按适用情况执行 source sync、ingest、chunk、content build、content lint、index build、index verify、validate、eval coverage 和 package verify。它会在 `state/pipeline-runs/` 下写入 run record，便于后续维护确认执行过什么。

调试或部分重建时，按顺序运行 authoring 命令：

```powershell
& $KbExe ingest --manifest <manifest> --json
& $KbExe chunking status --manifest <manifest> --json
& $KbExe chunk --manifest <manifest> --json
& $KbExe content build --manifest <manifest> --json
& $KbExe content lint --manifest <manifest> --check links --check images --check anchors --check metadata --json
& $KbExe index build --manifest <manifest> --target fts --json
```

`chunk` 后抽查 `chunks/chunks.jsonl`。`text` 必须仍是可读原文；`embedding_text` 必须按 manifest `embedding_text` 折叠链接、裸 URL、图片、视频和 asset path，避免把长 URL、图片路径或视频路径直接送入 embedding。修改 `embedding_text` policy 后，重新运行 `chunk` 并重建 vector index。

只有 embedding model、`kb-vector-service` 和 Qdrant 可用时，才使用 `--target all`：

```powershell
& $KbExe index build --manifest <manifest> --target all --json
& $KbExe index build --manifest <manifest> --target vector --vector-exe $VectorExe --json
```

Production-style Qdrant 发布要先构建 staging，通过验证后再 promote：

```powershell
& $KbExe index build --manifest <manifest> --profile prod --to-staging --json
& $KbExe index verify --manifest <manifest> --collection <staging-collection> --json
& $KbExe eval compare --manifest <manifest> --suite smoke --against <baseline.json> --json
& $KbExe index promote --manifest <manifest> --alias <alias> --collection <staging-collection> --json
```

已 promote 的 collection 在发布后检查失败，且记录了 previous collection 时，使用 `index rollback --alias <alias>`。

Portable KB package 应保留 normalized data、Markdown mirror、chunks、state、eval 和 standalone references。FTS 和 Qdrant 是派生索引。

## 验证新 KB

至少运行：

```powershell
& $KbExe validate --manifest <manifest> --json
& $KbExe content lint --manifest <manifest> --check all --json
& $KbExe index verify --manifest <manifest> --json
& $KbExe smoke-test --manifest <manifest> --json
& $KbExe audit --manifest <manifest> --json
```

Smoke set 应覆盖 KB primary/source language、预期术语、至少一个精确 identifier query 和一个概念查询。使用与真实查询相同的语言策略。

高质量 KB 还要运行：

```powershell
& $KbExe eval run --manifest <manifest> --suite smoke --json
& $KbExe eval report --manifest <manifest> --suite smoke --json
& $KbExe eval coverage --manifest <manifest> --suite smoke --json
& $KbExe eval baseline --manifest <manifest> --suite smoke --output <baseline.json> --json
& $KbExe eval compare --manifest <manifest> --suite smoke --against <baseline.json> --json
```

检索覆盖属于验收目标时，eval case 应包含 `topic`、`language` 和 `source_id`。声明完成前，运行 `quality-definition.md` 中的 handoff checklist。

## 注册或导出

Registry alias 为便利层。manifest 验证后再使用：

```powershell
& $KbExe register --manifest <manifest> --alias <alias> --json
```

除非用户要求其他 profile，否则用 `standard` profile 导出 portable skill bundle：

```powershell
& $KbExe package verify --path <kb-dir> --json
& $KbExe export-skill --manifest <manifest> --output <bundle.zip> --profile standard --json
```

不要打包本地模型文件、`kb-models.json`、registry 文件、Qdrant live storage、runtime logs、secrets、cookies 或机器特定绝对路径。
