# kbCli 命令参考

当任务需要短工作流示例之外的命令时，使用此 reference。如果命令面可能变化，优先运行 `kb.exe commands --json`。

所有示例默认使用 `SKILL.md` 中的运行时变量：

```powershell
$SkillFile = "<loaded SKILL.md full path>"
$SkillDir = Split-Path -Parent $SkillFile
$Runtime = & (Join-Path $SkillDir "scripts\resolve-kbcli.ps1") | ConvertFrom-Json
$KbExe = $Runtime.kb_exe
$VectorExe = $Runtime.vector_exe
$ModelRegistry = $Runtime.model_registry
```

如果 `$KbExe` 或 `$VectorExe` 缺失，skill 包不完整。不要从此 skill 编译；从 Release build 修复或替换 skill 包。

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
& $KbExe resolve --manifest <manifest> --symbol "<symbol>" --json
& $KbExe compare --manifest <manifest> --a "<topic-a>" --b "<topic-b>" --json
& $KbExe search-many --manifest <a.json> --manifest <b.json> --query "<query>" --json
```

标识符使用 `resolve`；版本或方案差异使用 `compare`；只有用户明确要求跨 KB 检索时才用 `search-many`。

Source-backed answer 中，`search` 是候选步骤，`fetch` 是证据步骤。不要只基于 search snippet 回答重要实现问题；先 fetch 支撑 chunks，并引用 `chunk_id` 和 `source_path`。

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

首次使用机器，或 GPU driver、ONNX Runtime packages、`DirectML.dll`、CUDA/cuDNN、embedding model、vector service binary 变化后，运行 `embedding optimize`。`--purpose query` 用于快速交互式查询；`--purpose index` 用于 build/rebuild 吞吐；`--purpose all` 用于完整刷新。Profile 存在本地 model registry 的当前 host key 下，不进入 portable KB manifest。后续 `embedding status` 显示 active profile 和 `optimization_profile_purposes`；未指定 provider 时，`vector serve --manifest <manifest>` 默认使用 query profile；vector index builds 在存在 index text-length buckets 时使用它们，并可为 bucket provider/device pairs 启动 build-only managed vector services。

首次自动化的 `--if-missing`、query/index strategy selection、profile interpretation 和 rerun triggers 见 `embedding-optimization.md`。

固定 DirectML/CUDA 设置和 troubleshooting flow 见 `gpu-providers.md`。

## 建库

- `init`：创建最小 KB skill skeleton。
- `source add/list/status/sync/update/remove`：管理 sources 和 fingerprints。
- `ingest` / `normalize`：把 sources 转成 normalized docs。
- `chunking status/set`：检查或更新 chunking strategy。
- `chunk`：生成稳定 chunks 和 links。
- `content build`：生成 Markdown mirror 和 markdown-map。
- `content lint`：验证 Markdown mirror links、images、anchors 和 metadata cleanup。
- `pipeline plan/run/resume`：运行或检查 recipe-driven build pipeline。

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
& $KbExe chunk --manifest <manifest> --changed-only --json
& $KbExe content build --manifest <manifest> --json
& $KbExe content lint --manifest <manifest> --check links --check images --check anchors --check metadata --json
& $KbExe pipeline plan --manifest <manifest> --recipe local-docs --target all --json
& $KbExe pipeline run --manifest <manifest> --recipe local-docs --target all --vector-exe $VectorExe --json
& $KbExe pipeline resume --manifest <manifest> --run-id <run-id> --json
```

常规文档 KB 创建中，sources 和 manifest policy 准备好后优先使用 `pipeline run`。大型 KB 且已存在 index optimization profile 时，仍使用默认 `bucket` vector build；调试或用户需要部分重建时再用单独命令。source、chunking 或 content 变化后，重建 stale indexes 并重新验证。

`chunk` 会写入可读原文 `text` 和派生向量输入 `embedding_text`。默认 `embedding_text` policy 会把 Markdown 链接折叠为标签，删除裸 URL，把图片/视频/裸 asset path 折叠成短描述；Qdrant vector build 使用 `embedding_text`，fetch 和 Markdown mirror 仍使用保留链接与媒体的 `text`。`chunking status --json` 会返回 effective policy 和 fingerprint；修改该 policy 后要重新 `chunk` 并重建 vector index。

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

vector dependencies 不可用时使用 `fts`。完整 `hybrid` readiness 使用 `all`。Production-style publication 中，先 build staging，运行 `index verify`、smoke/eval gates，再 promote alias。除非明确验证 staging collection，否则普通查询工作流不要指向 staging collection。

`index build --target vector` 默认执行 delta-safe 构建：扫描 Qdrant 中当前 `kb_id` 的 points，跳过 `chunk_id`、`chunk_fingerprint`、`embedding_text_policy_fingerprint` 与 `embedding_fingerprint` 全部匹配的 chunks，删除过期 points，只 embedding/upsert 新增或变更 chunks。进度写入 `state/vector-index-build-state.json`；如果 `kb.exe` 被杀掉或机器中断，下次重跑同一命令会基于 Qdrant 已完成 points 继续。需要强制丢弃现有向量时，先显式运行 `index clean --target vector`。

`index clean --target vector` 只清理 vector 派生索引并标记 vector stale；不会使 FTS 变脏。

`index verify` 应视为 vector integrity gate。它检查 Qdrant collection 可用性、point count 与 chunk count、required payload fields、required payload indexes、embedding fingerprint 和少量 point payload sample。它不会让 Qdrant 成为 source of truth；source docs、chunks 和 content mirror 仍然是可重建资产。

Promotion 前验证 staging collection 时使用 `index snapshot --collection <collection>`。当 Qdrant node 可从 server-side snapshot path 恢复，且下载 snapshot file 会很慢或很大时，添加 `--no-download`。`index snapshot-verify` 会恢复到目标 collection 并报告 `data.valid`；即使命令返回 JSON，`valid=false` 也视为 restore drill 失败。

存在匹配的 index optimization profile 时，vector index builds 会报告 `data.vector.build.index_strategy_available=true`、`optimized_services_used`、`managed_services`、`build_mode` 和 `bucket_usage`。当前唯一 build mode 是默认 `bucket`：按 chunk 文本长度 bucket 顺序处理，使用 profile 中对应该 bucket 的最佳 provider/device 和 batch size。Vector build 输出 `timings`：`stages` 覆盖 binding、Qdrant collection、chunk load、增量扫描、managed service startup 和 progress write；`batches_total`/`batches_by_endpoint` 覆盖 point shell、direct-upsert attempt、embedding、attach vectors、Qdrant upsert 和实际吞吐；`bucket_usage` 同步写入各 bucket 的实际耗时。非 managed endpoint 默认尝试 direct upsert，由 `kb-vector-service` 直接写 Qdrant；输出 `direct_upsert_batches/items` 可确认是否命中，服务端会回传 direct 路径的 `embedding_ms`、`attach_vectors_ms` 和 `qdrant_upsert_ms`，设置 `KB_EMBEDDING_DIRECT_UPSERT=false` 可关闭。CLI 自己拉起的 managed endpoint 默认使用稳定 JSON response 并由 CLI 端写入 Qdrant；`KB_MANAGED_EMBEDDING_TRANSPORT=shared_memory|binary|auto` 只作为显式性能实验开关使用，真实大库建库时若出现 Release 崩溃应立即回退 `json`。managed direct-upsert 只作为显式实验开关使用：设置 `KB_MANAGED_EMBEDDING_DIRECT_UPSERT=true` 后才尝试。长期运行的 manifest endpoint 仍按 `KB_EMBEDDING_TRANSPORT` 使用 auto/shared-memory/binary/JSON。Query-only profile 有意不足以触发 managed index services；只有需要强制旧的单 manifest endpoint 路径时，才传 `--no-optimized-vector-services`。

细粒度 embedding 内部计时只用于开发分析，默认关闭。需要拆分 `embedding_ms` 时，临时设置 `KB_VECTOR_DEV_TIMINGS=1`，或启动 `kb-vector-service --dev-timings`。开启后 JSON/SHM/direct-upsert 响应会包含 `dev_timings` 或 `timings.embedding_detail`，字段包括 `cache_lookup_ms`、`dedupe_ms`、`tokenize_ms`、`input_buffer_ms`、`tensor_build_ms`、`run_wait_ms`、`ort_run_ms`、`output_extract_ms`、`normalize_ms`、`cache_store_ms`、`token_positions`、`cache_hits/misses` 和 `computed_count`。为了拿到完整明细，CLI 在 `KB_VECTOR_DEV_TIMINGS=1` 下会走 JSON embedding response；正常建库不要开启该变量。

## 质量、打包与维护

- `validate`、`smoke-test`、`audit`：最低质量门禁。
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

维护高价值 KB 时，变更后的最低 gate 是：`content lint`、`index verify`、`validate`、`eval coverage`、存在 baseline 时的 `eval compare`，以及 `package verify`。`pipeline run --target all` 会执行常用序列，并在 KB `state/pipeline-runs/` 目录写入 run record。
