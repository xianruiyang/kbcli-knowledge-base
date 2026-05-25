# 高质量 KB 完成定义

创建新 KB、刷新重大来源集合，或判断 KB 是否足以在新 Codex 对话中使用时，使用此 reference。

命令示例使用 `SKILL.md` 中定义的随包 Release 运行时变量 `$KbExe` 和 `$VectorExe`。

高质量 KB 必须有来源支撑，能用正确语言查询，可复现、可维护，并能证明重要问题能检索到正确证据。

## 输入澄清

构建前先确认：

- KB 必须支持的领域和用户工作流；
- primary language 和 source languages；
- authority order，例如官方文档优先于博客、当前 policy 优先于旧 policy、repository source 优先于生成摘要；
- 预期回答风格、引用需求，以及领域是否高风险；
- source freshness window 和 update owner；
- 不得进入 KB 的敏感数据、授权限制、secrets、credentials、private URLs 或 generated files。

如果用户给的是混合文件夹，`source add` 前先检查目录树。除非明确有意，不要把 build outputs、generated indexes、runtime logs、cache folders、model files、package archives、没有文本价值的 screenshots 或旧 KB output 当作 source evidence 导入。

## 来源质量

高质量 KB source set 应具备：

- 足够覆盖用户要求 KB 支持的工作流；
- KB 内稳定 source paths，或对 external paths 有明确 manifest policy；
- 可读 normalized text，而不是只有图片或破损 markup；
- 保留原始 identifiers、headings、code names、URLs 和 version labels；
- 处理 duplicate 和 stale source；
- 为转换、过滤、清理、链接重写、图片复制和未恢复 asset 保留 source-preparation record。
- 媒体资源只保留对正文理解有证据价值的内容；静态图片默认 JPEG 压缩，透明源图白底合成，PNG 只在 JPEG 明显破坏截图/线稿/透明信息时例外保留并记录原因；GIF/动画非必要不保留，必要时优先转压缩 WebP 或关键帧 JPEG。

优先选择可引用来源，并保留原始文档边界，使回答能指向可识别证据。

## Manifest 与 Skill

首次完整 vector build 前，manifest 和 KB skill 应定义：

- `primary_language`、`source_languages` 和 `query_language_policy`；
- `domain` 和 `authority_policy`；
- `payload_schema.required_fields` 和 `payload_schema.required_payload_indexes`；
- Qdrant `publish.alias`，或不使用 alias 的明确理由；
- embedding model、dimension、normalize、max tokens 和 chunking policy；
- `embedding_text` policy，确保向量化输入折叠链接、裸 URL、图片、视频和 asset path，但 source text 与 Markdown mirror 仍保留可读链接和媒体引用；
- 紧凑的 KB `SKILL.md`，声明 scope、Hybrid-first retrieval、source-language search、fetch-before-answer 和 downgrade behavior；
- KB `SKILL.md` 明确依赖 `kbcli-knowledge-base`，包含 `$KbExe`/`$VectorExe`/manifest 解析流程，且所有命令示例使用 `& $KbExe ...`；
- KB `SKILL.md`、query guide 和 maintenance guide 中不得出现 `kb search`、`kb fetch`、`kb index build` 等裸 `kb ...` 命令示例；
- 可选但推荐提供 `scripts/resolve-kbcli-runtime.ps1`，作为当前 KB 到 `kbcli-knowledge-base/scripts/resolve-kbcli.ps1` 的桥接脚本；
- `references/topic-map.md`，包含主要 topics、aliases、exact identifiers 和可能的 user queries；
- `references/standalone-guide.md`，用于无隐藏对话上下文的使用场景。

不要把本地模型路径、provider/device 选择、registry alias、Qdrant live storage、secrets、cookies、runtime logs 或本地绝对路径写入 portable KB output。

## Chunk 质量

`chunk` 后抽查足够 chunks，确认：

- chunks 保留回答所需的有意义 heading 和局部上下文；
- chunks 不被导航、重复 boilerplate、metadata 或破损转换产物主导；
- 可行时，exact identifiers 与其解释保留在同一个 chunk 中；
- 长流程没有被切得过碎，导致步骤丢失前置条件；
- 可行时，code/API/reference material 保留 signature、class/function names、parameters 和 notes；
- `embedding_text` 不含无意义长 URL、图片路径或视频路径，且保留链接标签、图片 alt/caption、视频 caption 或有意义文件名；
- source path、language、adapter、title 和 fingerprint metadata 存在。

如果 chunk quality 弱，先调整 source cleanup 或 chunking，再构建索引。不要依赖 vector search 修复糟糕的 source conversion。

## Eval 最小要求

每个高质量 KB 都要创建 `eval/smoke.jsonl`。Case 应反映真实用户工作，而不仅是通用 keyword 检查。

最低 suite：

- 一个 exact identifier 或 title lookup；
- 一个使用领域术语的概念问题；
- 如果用户通常用另一种语言提问，包含一个 source-language query；
- 一个常见 task/workflow 问题；
- 一个 negative 或 boundary query，此时 KB 应说明证据不足；
- 每个重要 source group 至少一个 source coverage case；
- 多语言 KB 每个重要语言至少一个 case。

每个 case 应包含 `query`、`must_include`、已知时的 `expected_chunk_id`，以及可用时的 `topic`、`language` 和 `source_id`。source priority 重要时，添加 `expected_source_type` 或 authority metadata。

高风险或频繁更新 KB 还要保留 regression baseline：

```powershell
& $KbExe eval baseline --manifest <manifest> --suite smoke --output <baseline.json> --json
& $KbExe eval compare --manifest <manifest> --suite smoke --against <baseline.json> --json
```

## 构建与验证门禁

高质量 KB 的常规 gate：

```powershell
& $KbExe pipeline run --manifest <manifest> --recipe local-docs --target all --vector-exe $VectorExe --json
& $KbExe content lint --manifest <manifest> --check all --json
& $KbExe index verify --manifest <manifest> --json
& $KbExe validate --manifest <manifest> --json
& $KbExe smoke-test --manifest <manifest> --json
& $KbExe eval run --manifest <manifest> --suite smoke --json
& $KbExe eval coverage --manifest <manifest> --suite smoke --json
& $KbExe audit --manifest <manifest> --json
& $KbExe package verify --path <kb-dir> --json
```

如果 vector dependencies 不可用，构建 `--target fts`，记录 Hybrid/vector 未完成；vector indexing 通过前，不要声称完整 Hybrid readiness。

Production-style Qdrant 使用场景中，先构建 staging collection，verify，运行 eval compare，再 promote alias。保留 rollback 能力。

## 手动检索检查

交接前，至少用 KB/source language 运行两个真实 Hybrid query，然后 fetch top evidence chunks：

```powershell
& $KbExe search --manifest <manifest> --query "<source-language query>" --mode hybrid --top-k 5 --candidate-k 40 --json
& $KbExe fetch --manifest <manifest> --chunk-id <chunk-id> --include-source --include-links --json
```

检查 fetched text 是否实际支撑预期回答。Search snippets 不够。

## 交接

在 runtime log 或 KB state 中记录最终状态：

- manifest path 和 KB id；
- source set 和 preparation record；
- build command 或 pipeline run id；
- chunk count 和 index status；
- Qdrant collection 或 alias；
- embedding model，以及是否使用 query/index optimization；
- validation/eval/package 结果；
- 已知缺口、跳过的 gates、不可用服务或有意不支持的 topics；
- update instructions，尤其是是否使用 `source remove`、`--changed-only` 和 safe full index refresh。

最终回复先说结果，再给 validation evidence，最后列出剩余限制。

## 风险标记

除非明确记录为有意选择，否则以下任一情况成立时，不要称 KB 为 high-quality：

- source provenance 不清楚；
- cleaned source text 未保存；
- 将被复用的 KB 缺少 eval suite；
- 只有 keyword search 可用，却描述成 Hybrid-ready；
- Qdrant point count 与 chunk count 不匹配；
- source-language query behavior 未测试；
- fetched chunks 不支撑最终 claims；
- 通过直接编辑 JSONL 或 Qdrant 完成 source deletion/update；
- portable package 包含本机状态或 secrets；
- substantial warnings 未记录原因就被忽略。
