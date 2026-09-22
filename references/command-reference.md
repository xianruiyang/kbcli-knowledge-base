# kbCli 命令参考

当任务需要短工作流示例之外的命令时，使用此 reference。如果命令面可能变化，优先运行 `kb.exe commands --json`。

所有示例使用 [SKILL.md](../SKILL.md) 中解析的运行时变量。本文是按需查阅的命令目录，不是顺序执行清单；参数以实际运行时 help 为准。

## 运行时、读取与查询

- `doctor`：检查 CLI runtime 和 native dependencies。
- `commands`：列出已实现命令面。
- `version`：输出 CLI 版本。
- `info`：汇总 manifest 和 package capabilities。
- `search`：运行 `keyword`、`vector`、`hybrid` 或 `structured` 检索。
- `fetch`：按 chunk id 获取完整 chunk/source/link evidence。
- `resolve`：对 API 名、符号、config key、error 或术语做近似精确查找。
- `compare`：检索两个 topic 的证据并分组差异。
- `search-many`：显式查询多个 KB target。

示例：

```powershell
& $KbExe doctor --json
& $KbExe commands --json
& $KbExe version --json
& $KbExe info --manifest <manifest> --json
& $KbExe search --manifest <manifest> --query "<query>" --mode hybrid --top-k 8 --candidate-k 40 --json
& $KbExe search --manifest <manifest> --query "<query>" --filter source_type=official_docs --language zh-CN --json
& $KbExe fetch --manifest <manifest> --chunk-id <chunk-id> --include-source --include-links --json
& $KbExe fetch --manifest <manifest> --chunk-id <chunk-id> --neighbors 3 --include-source --include-links --json
& $KbExe resolve --manifest <manifest> --symbol "<symbol>" --json
& $KbExe compare --manifest <manifest> --a "<topic-a>" --b "<topic-b>" --json
& $KbExe search-many --manifest <a.json> --manifest <b.json> --query "<query>" --json
```

标识符使用 `resolve`；版本或方案差异使用 `compare`；只有用户明确要求跨 KB 检索时才用 `search-many`。

Source-backed answer 中，`search` 是候选步骤，`fetch` 是证据步骤。不要只基于 search snippet 回答重要实现问题；先 fetch 支撑 chunks，并引用 `chunk_id` 和 `source_path`。

`fetch --neighbors N` 沿 `chunk-links.jsonl` 返回同一文档内每个方向最多 N 个邻居 ID，按距目标由近到远排列；N 必须非负。文档首尾不跨到其他文档。缺失、循环或跨文档的邻接记录会返回明确错误，需要在获授权的维护中通过 `chunk` 重建邻接关系，再按需重建失效索引。

`search` 和 `fetch` 按命中 ID 从原始 chunks JSONL 读取正文。FTS 构建同时生成 SQLite offset lookup；lookup 缺失或失效时，查询会带 warning 逐行扫描 JSONL，仅为命中的 ID 加载正文，找到全部目标后停止，不在只读查询中写索引。使用 `index build --target fts` 重建该派生 lookup。

## Registry 与目标选择

- `register`、`list`、`unregister`：管理本地 alias。
- `registry list/register/unregister`：等价 registry subcommands。
- `discover`：扫描显式 root 下的 manifests；不要作为查询热路径。

示例：

```powershell
& $KbExe register --manifest <manifest> --alias <alias> --json
& $KbExe list --json
& $KbExe unregister --kb <alias> --json
& $KbExe registry register --manifest <manifest> --alias <alias> --json
& $KbExe registry list --json
& $KbExe registry unregister --kb <alias> --json
& $KbExe discover --root <dir> --register --json
```

自动化工作优先使用 `--manifest`。只有验证 alias 后才使用 `--kb`。

## Model、Embedding 与 Vector

- `model list/register/verify/pull`：管理存放在 `kb.exe` 旁边的 model registry。
- `embedding status/bind/set/test/optimize`：对比或更新 manifest embedding requirements、测试 inference、保存按机器的 optimization profile。
- `vector status/serve/stop`：检查和管理本地 vector service。

示例：

```powershell
& $KbExe model list --json
& $KbExe model register --model BAAI/bge-m3 --format onnx --precision fp32 --dimension 1024 --path <model-dir> --json
& $KbExe model verify --path <model-dir> --json
& $KbExe model pull --model BAAI/bge-m3 --target <model-dir> --json
& $KbExe embedding status --manifest <manifest> --json
& $KbExe embedding bind --manifest <manifest> --model-path <model-dir> --json
& $KbExe embedding set --manifest <manifest> --model BAAI/bge-m3 --dimension 1024 --max-tokens 1536 --json
& $KbExe embedding test --manifest <manifest> --json
& $KbExe embedding optimize --manifest <manifest> --vector-exe $VectorExe --providers cpu --purpose query --quick --json
& $KbExe embedding optimize --manifest <manifest> --vector-exe $VectorExe --providers cpu --purpose index --quick --json
& $KbExe vector status --manifest <manifest> --json
& $KbExe vector serve --manifest <manifest> --strategy query --json
& $KbExe vector serve --manifest <manifest> --strategy index --json
& $KbExe vector stop --json
```

修改 embedding requirements 会让 vector indexes stale。信任 `hybrid` 前先重建 vector indexes。

随包 Release 运行时支持 CPU。只有使用 provider-capable runtime package 时，才使用 `--execution-provider cuda`、`--execution-provider dml` 或 `auto`；见 `gpu-providers.md`。

需要优化查询延迟或建库吞吐时，按 [Embedding 性能调优](embedding-optimization.md) 选择 query/index profile。普通查询不要求先跑 benchmark；profile 属于本机 registry，不进入可迁移 manifest。

Provider 依赖与故障处理见 [GPU providers](gpu-providers.md)。

## 建库

- `init`：创建最小 KB skill skeleton。
- `source add/list/status/sync/update/remove`：管理 sources 和 fingerprints。
- `ingest` / `normalize`：把 sources 转成 normalized docs。
- `chunking status/set`：检查或更新 chunking strategy。
- `chunk`：生成稳定 chunks 和 links。
- `content build`：生成 Markdown mirror 和 markdown-map。
- `content lint`：验证 Markdown mirror links、images、anchors 和 metadata cleanup。
- `pipeline plan/run/resume/inspect`：规划、运行、恢复或只读检查 recipe-driven build pipeline。

示例：

```powershell
& $KbExe init --kb-id <id> --name "<name>" --output <dir> --json
& $KbExe source add --manifest <manifest> --type markdown --path <path> --title "<title>" --json
& $KbExe source list --manifest <manifest> --json
& $KbExe source status --manifest <manifest> --json
& $KbExe source sync --manifest <manifest> --json
& $KbExe source update --manifest <manifest> --source-id <id> --path <path> --json
& $KbExe source remove --manifest <manifest> --source-id <id> --json
& $KbExe ingest --manifest <manifest> --changed-only --json
& $KbExe chunking status --manifest <manifest> --json
& $KbExe chunking set --manifest <manifest> --target-tokens 900 --max-tokens 1400 --overlap-tokens 120 --json
& $KbExe chunk --manifest <manifest> --model-registry <kb-models.json> --changed-only --json
& $KbExe content build --manifest <manifest> --json
& $KbExe content lint --manifest <manifest> --check links --check images --check anchors --check metadata --json
& $KbExe pipeline plan --manifest <manifest> --recipe local-docs --target all --json
& $KbExe pipeline run --manifest <manifest> --recipe local-docs --target all --vector-exe $VectorExe --json
& $KbExe pipeline inspect --manifest <manifest> --run-id <run-id> --json
& $KbExe pipeline resume --manifest <manifest> --run-id <run-id> --json
```

常规文档 KB 创建中，sources 和 manifest policy 准备好后优先使用 `pipeline run`。大型 KB 且已存在 index optimization profile 时，仍使用默认 `bucket` vector build；调试或用户需要部分重建时再用单独命令。source、chunking 或 content 变化后，重建 stale indexes 并重新验证。

Pipeline 的 ingest/chunk 默认复用未变化产物。`ingest --changed-only` 按文件内容与 adapter 配置校验，处理新增、修改和删除；`content build` 只写变化内容，并仅删除既有 markdown-map 登记的消失产物。单独运行不带 `--changed-only` 的 ingest/chunk 可强制重新处理。

`pipeline resume` 会写入知识库并从失败或中断步骤继续，保留已完成步骤；只接受 schema version 2 的 `failed` / `running` checkpoint。恢复时要求原始来源、manifest、当前步骤输入与记录一致；输入已变化应启动新 run。恢复向量构建时沿用原来的 model registry 和 vector 参数。只想查看记录（含旧格式）时使用 `pipeline inspect`。

`chunk` 会写入可读原文 `text` 和派生向量输入 `embedding_text`。默认 `embedding_text` policy 会把 Markdown 链接折叠为标签，删除裸 URL，把图片/视频/裸 asset path 折叠成短描述；Qdrant vector build 使用 `embedding_text`，fetch 和 Markdown mirror 仍使用保留链接与媒体的 `text`。`chunking status --json` 会返回 effective policy 和 fingerprint；修改该 policy 后要重新 `chunk` 并重建 vector index。

有本地模型绑定时，`chunk` 使用实际 SentencePiece tokenizer，并为 title/source/document 前缀和 CLS/SEP 预留预算。超长文本继续拆分为可检索 chunks，原文保留。无模型时允许生成明确标记为 estimated 的离线 chunks；构建向量前必须绑定 tokenizer 并重新 chunk。向量构建在访问 Qdrant 前验证全部完整输入的真实 token 上限，旧版超预算 chunks 会明确报错。

## 索引

- `index status/build/verify/clean/snapshot/restore`：管理 FTS 和 vector 派生索引。
- `index promote/rollback`：发布或回滚 Qdrant collection alias。
- `index snapshot-verify`：用于 snapshot restore drill 检查的命令面入口。
- `rebuild-index`：构建全部 indexes 的 alias。
- `validate-index`：检查派生索引可用性与兼容性。

示例：

```powershell
& $KbExe index status --manifest <manifest> --json
& $KbExe index build --manifest <manifest> --target fts --json
& $KbExe index build --manifest <manifest> --target all --json
& $KbExe index build --manifest <manifest> --target vector --vector-exe $VectorExe --json
& $KbExe index build --manifest <manifest> --profile prod --to-staging --json
& $KbExe index verify --manifest <manifest> --json
& $KbExe index verify --manifest <manifest> --collection <collection> --json
& $KbExe index promote --manifest <manifest> --alias <alias> --collection <collection> --json
& $KbExe index rollback --manifest <manifest> --alias <alias> --json
& $KbExe index clean --manifest <manifest> --target vector --json
& $KbExe index snapshot --manifest <manifest> --output <dir> --json
& $KbExe index snapshot --manifest <manifest> --collection <collection> --output <dir> --json
& $KbExe index snapshot --manifest <manifest> --collection <collection> --output <dir> --no-download --json
& $KbExe index snapshot --manifest <manifest> --output <dir> --skip-qdrant --json
& $KbExe index snapshot-verify --manifest <manifest> --snapshot <snapshot-file> --json
& $KbExe index snapshot-verify --manifest <manifest> --snapshot <snapshot-dir> --collection <temporary-collection> --json
& $KbExe index restore --manifest <manifest> --input <dir> --json
& $KbExe rebuild-index --manifest <manifest> --json
& $KbExe validate-index --manifest <manifest> --json
```

vector dependencies 不可用时使用 `fts`。完整 `hybrid` readiness 使用 `all`。Production-style publication 中，先 build staging，按发布任务约定检查 staging，再 promote alias。除非明确验证 staging collection，否则普通查询工作流不要指向 staging collection。

`index build --target vector` 默认执行 delta-safe 构建：扫描 Qdrant 中当前 `kb_id` 的 points，跳过 `chunk_id`、`chunk_fingerprint`、`embedding_text_policy_fingerprint`、`embedding_fingerprint` 及完整输入／元数据的 `point_fingerprint` 全部匹配的 chunks，只 embedding/upsert 新增或变更 chunks，全部替换批次成功后才删除退休 IDs。同 ID 的变更点由 upsert 覆盖，不会在末尾误删。进度写入 `state/vector-index-build-state.json`；中断后重跑同一命令可继续。增量写入不提供整库原子切换；需要该保证时使用 staging/alias 发布流程。需要强制丢弃现有向量时，先显式运行 `index clean --target vector`。

向量指纹包含模型文件内容、tokenizer 和影响向量的语义配置；endpoint、batch size 等执行设置不触发重新 embedding。新指纹版本会使旧格式 points 在下一次获授权的构建中重建。模型内容按构建校验一次，服务首次加载该身份时再校验；建库期间不要替换模型文件。服务须支持 `/health` 的 `model_artifact_identity=true`，旧服务需启动匹配的新运行时。自定义 registry 下的 `index verify`、`index snapshot-verify`、`validate-index` 同样传 `--model-registry`。

`index clean --target vector` 只清理 vector 派生索引并标记 vector stale；不会使 FTS 变脏。

向量写入完成后的统计读取失败不会撤销已完成的写入。构建结果和 state 中未知的 `point_count` 为 `null`（不是 0），不可读取的 `collection_info` 为 `null`；`statistics_warnings` 和外层 warnings 说明具体失败。消费者应区分未知计数与空 collection。

`index verify` 用于检查向量索引完整性。它检查 Qdrant collection 可用性、point count 与 chunk count、required payload fields、required payload indexes、embedding fingerprint 和少量 point payload sample。它不会让 Qdrant 成为 source of truth；source docs、chunks 和 content mirror 仍然是可重建资产。

Promotion 前验证 staging collection 时使用 `index snapshot --collection <collection>`。当 Qdrant node 可从 server-side snapshot path 恢复，且下载 snapshot file 会很慢或很大时，添加 `--no-download`。`index snapshot-verify` 会恢复到目标 collection 并报告 `data.valid`；即使命令返回 JSON，`valid=false` 也视为 restore drill 失败。

## 质量、打包与维护

`smoke-test`、`eval run`、`index verify` 和 `validate-index` 完成检查后，顶层 `check_status` 为 `passed` 或 `failed`，`ok` 与检查结果一致；通过时退出码为 0，未通过时为 3，错误码为 `KB_CHECK_FAILED`，详细报告仍保留在 `data` 中。此约定只表达调用者主动执行的检查结果，不自动执行检查，也不增加构建或查询前置门禁。旧运行时及其他命令仍需按各自的 `data.passed` / `data.valid` 等字段判断。

- `validate`、`smoke-test`、`audit`：结构、检索样本与审计检查，按任务需要选择。
- `eval run/report/coverage/baseline/compare`：检索回归与覆盖检查。
- `package inspect/verify`、`export-skill`、`import-skill`：package lifecycle。
- `backup create/restore`：backup lifecycle；除非用户要求 `--replace`，否则恢复到新目录。
- `diff`、`repair`、`migrate-manifest`：长期维护。
- `lock status`、`changelog add/list`：write-lock 和 release tracking。

示例：

```powershell
& $KbExe validate --manifest <manifest> --json
& $KbExe smoke-test --manifest <manifest> --json
& $KbExe audit --manifest <manifest> --json
& $KbExe eval run --manifest <manifest> --suite smoke --json
& $KbExe eval report --manifest <manifest> --suite smoke --json
& $KbExe eval coverage --manifest <manifest> --suite smoke --json
& $KbExe eval baseline --manifest <manifest> --suite smoke --output <baseline.json> --json
& $KbExe eval compare --manifest <manifest> --suite smoke --against <baseline.json> --json
& $KbExe package inspect --path <zip-or-dir> --json
& $KbExe package verify --path <zip-or-dir> --json
& $KbExe export-skill --manifest <manifest> --output <bundle.zip> --profile standard --json
& $KbExe import-skill --path <bundle.zip> --output <dir> --alias <alias> --json
& $KbExe backup create --manifest <manifest> --output <backup.zip> --json
& $KbExe backup restore --input <backup.zip> --output <dir> --json
& $KbExe diff --manifest <manifest> --against <old-bundle-or-manifest> --json
& $KbExe repair --manifest <manifest> --json
& $KbExe migrate-manifest --manifest <manifest> --json
& $KbExe lock status --manifest <manifest> --json
& $KbExe changelog add --manifest <manifest> --message "<message>" --json
& $KbExe changelog list --manifest <manifest> --json
```

默认 export profile 是 `standard`。不要打包本地模型、registry 文件、Qdrant live storage、runtime logs、secrets、cookies 或机器特定路径。

检查选择见 [质量与验收](quality-definition.md)，打包范围及本机文件排除责任见 [维护指南](maintenance.md)。不把本页示例作为必须逐条执行的清单。
