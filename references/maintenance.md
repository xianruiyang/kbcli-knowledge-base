# kbCli 维护与运维

更新、故障排查、修复、package 检查和长期 KB 维护时，使用此 reference。

命令示例使用 `SKILL.md` 中定义的随包 Release 运行时变量 `$KbExe` 和 `$VectorExe`。

## 更新流程

编辑前检查状态：

```powershell
& $KbExe info --manifest <manifest> --json
& $KbExe source status --manifest <manifest> --json
& $KbExe index status --manifest <manifest> --json
```

Source 变化后：

```powershell
& $KbExe source sync --manifest <manifest> --json
& $KbExe ingest --manifest <manifest> --changed-only --json
& $KbExe chunk --manifest <manifest> --changed-only --json
& $KbExe content build --manifest <manifest> --json
& $KbExe index build --manifest <manifest> --target all --json
```

只修改 manifest `embedding_text` policy 时，也要运行 `chunk --changed-only` 或完整 pipeline。该 policy 影响 `chunks/chunks.jsonl` 中的 `embedding_text` 和 vector embedding fingerprint；FTS 与可读 Markdown 不需要因为链接折叠策略变化而改变，但 vector index 必须重建。

Source 删除时，使用 CLI tombstone 路径，不要手动删 rows：

```powershell
& $KbExe source remove --manifest <manifest> --source-id <source-id> --json
& $KbExe ingest --manifest <manifest> --changed-only --json
& $KbExe chunk --manifest <manifest> --changed-only --json
& $KbExe content build --manifest <manifest> --json
& $KbExe index build --manifest <manifest> --target all --json
```

当前 kbCli update policy 是 source/chunk 增量，vector index 也是 delta-safe。`ingest --changed-only` 和 `chunk --changed-only` 复用未变化 source/docs；`index build --target vector` 会扫描当前 Qdrant collection 中同 `kb_id` 的 points，复用 `chunk_id`、`chunk_fingerprint`、`embedding_text_policy_fingerprint` 与 `embedding_fingerprint` 全部匹配的 points，只对新增或变更 chunks 做 embedding/upsert，并删除已删除、过期或 fingerprint 不匹配的 points。

Vector 构建过程中会写入 `state/vector-index-build-state.json`。如果构建进程被完整停止或杀掉，保留已成功 upsert 的 Qdrant points；下次重新运行同一个 `index build --target vector` 或 pipeline 时，会像增量更新一样跳过已完成 points，只继续缺失或变更部分。新版本写锁会记录 `pid`；同主机死进程留下的 `state/kb.lock` 会在下次写入命令中自动清理。

只有在需要主动丢弃现有向量时才先运行 `index clean --target vector`。`kb_id`、embedding model/dimension、`embedding_text` policy 或 chunking 策略整体变化时，当前 chunks 通常会全部变为待处理；这仍会通过 delta planner 删除旧 fingerprint points 后重建当前 chunk set。

如果 source path 暂时缺失，先诊断缺失路径，再视为有意删除。真实删除优先使用显式 `source remove`，避免网络盘或外置盘短暂不可用在维护时静默删除 normalized docs 和 chunks。

Vector dependencies 不可用时使用 `--target fts`。说明 vector/hybrid retrieval 会保持 stale 或 unavailable，直到 vector indexing 成功。

常规 full rebuild 优先使用 recorded pipeline，不手动串联所有命令：

```powershell
& $KbExe pipeline run --manifest <manifest> --recipe local-docs --target all --vector-exe $VectorExe --json
& $KbExe pipeline resume --manifest <manifest> --run-id <run-id> --json
```

`state/pipeline-runs/` 下的 run record 是交接资产，记录重建了什么、哪些 gate 通过、还剩哪些 warnings。

重大 rebuild 前后，在项目 runtime log 中记录 effective manifest path、command set、service state、run id 和 validation result。当任务改变 source content、chunks、indexes、embedding profiles、Qdrant aliases 或 package state 时，这是必需项。

## 模型与向量检查

检查 model binding：

```powershell
& $KbExe embedding status --manifest <manifest> --json
```

需要时绑定本地 model path：

```powershell
& $KbExe embedding bind --manifest <manifest> --model-path <model-dir> --json
```

首次设置、driver/runtime 变化、model 变化或 vector service binary 变化后，创建或刷新 per-machine embedding optimization profile：

```powershell
& $KbExe embedding optimize --manifest <manifest> --vector-exe $VectorExe --providers cpu --purpose index --quick --if-missing --json
```

Optimization profile 是保存在 model registry 中的本机状态。不要打包进 portable KB bundle。交互式查询使用 `--purpose query`；build/rebuild 性能优化使用 `--purpose index`；机器空闲时完整刷新使用 `--purpose all`。

完整 first-run 和 active optimization policy 见 `embedding-optimization.md`。

DirectML/CUDA 设置、provider-specific validation 和常见 GPU failures 见 `gpu-providers.md`。

运行 service smoke test：

```powershell
& $KbExe vector status --manifest <manifest> --json
& $KbExe embedding test --manifest <manifest> --json
```

如果 `vector status` 显示 model 已配置但 service unavailable，启动：

```powershell
& $KbExe vector serve --manifest <manifest> --strategy index --json
```

常规 authoring 和重复 query sessions 中，复用 Qdrant 和 `kb-vector-service`，不要反复停止启动。将它们视为本地开发服务，除非用户要求关闭、进程 wrong/stale，或服务只为一次性 smoke test 启动。

如果 Docker、WSL、Qdrant 或 `kb-vector-service` 在 KB 工作中崩溃，先诊断再重启大范围服务或清理 indexes。记录失败命令、`vector status`、`index status`、可用时的 Docker/Qdrant logs，以及服务是用户启动还是任务启动。只有确认 source docs、chunks 和 manifest 完整后，才删除或重建派生 indexes。

## 质量门禁

KB content、chunking、manifest、indexing 或 packaging 变化后运行：

```powershell
& $KbExe content lint --manifest <manifest> --check all --json
& $KbExe index verify --manifest <manifest> --json
& $KbExe validate --manifest <manifest> --json
& $KbExe smoke-test --manifest <manifest> --json
& $KbExe audit --manifest <manifest> --json
& $KbExe package verify --path <kb-dir-or-zip> --json
```

检索质量重要时运行 eval：

```powershell
& $KbExe eval run --manifest <manifest> --suite smoke --json
& $KbExe eval coverage --manifest <manifest> --suite smoke --json
& $KbExe eval compare --manifest <manifest> --suite smoke --against <baseline.json> --json
```

只有人工接受当前检索行为后，才创建或刷新 baseline：

```powershell
& $KbExe eval baseline --manifest <manifest> --suite smoke --output <baseline.json> --json
```

每个 smoke/regression case 应带有 `topic`、`language` 和 `source_id`，使 `eval coverage` 能发现 suite 意外变窄。

## Qdrant 发布与回滚

Production-style Qdrant 发布不要直接覆盖 active collection。先构建 staging collection，verify，运行 retrieval gates，再 promote alias：

```powershell
& $KbExe index build --manifest <manifest> --profile prod --to-staging --json
& $KbExe index verify --manifest <manifest> --collection <staging-collection> --json
& $KbExe eval compare --manifest <manifest> --suite smoke --against <baseline.json> --json
& $KbExe index promote --manifest <manifest> --alias <alias> --collection <staging-collection> --json
```

如果 post-release checks 失败且记录了 previous collection：

```powershell
& $KbExe index rollback --manifest <manifest> --alias <alias> --json
```

Qdrant 仍然是派生索引。保留 source docs、chunks、content mirror、manifest 和 state 作为可重建真源。

## 修复、Diff、备份

风险维护前使用 `diff`：

```powershell
& $KbExe diff --manifest <manifest> --against <old-bundle-or-manifest> --json
```

`repair` 只用于可重建 state 和派生 metadata：

```powershell
& $KbExe repair --manifest <manifest> --json
```

批量 update 或 replace 前创建 backups：

```powershell
& $KbExe backup create --manifest <manifest> --output <backup.zip> --json
```

本地派生 indexes：

```powershell
& $KbExe index snapshot --manifest <manifest> --output <dir> --json
& $KbExe index snapshot --manifest <manifest> --collection <collection> --output <dir> --json
& $KbExe index snapshot --manifest <manifest> --collection <collection> --output <dir> --no-download --json
& $KbExe index snapshot-verify --manifest <manifest> --snapshot <dir-or-file> --collection <temporary-collection> --json
& $KbExe index snapshot --manifest <manifest> --output <dir> --skip-qdrant --json
```

Promotion 前使用 `--collection` snapshot 并验证 staging collection。当 Qdrant node 可从自己的 snapshot location 恢复，且 snapshot file 太大或下载太慢时，加 `--no-download`。检查 `snapshot-verify` 输出中的 `data.valid`；必须为 true 才能把 drill 计为通过。

当 Qdrant snapshot 太慢、太大、被本地 node 阻塞，或因 vector collection 可从 chunks 重建而不必要时，使用 `--skip-qdrant`。在 runtime log 中记录该限制。

默认恢复到新目录。只有用户明确要求覆盖现有 KB 时，才使用 `--replace`。

## 运行日志

调试时设置 `KB_LOG_DIR` 到项目日志目录，使 console JSON 保持可解析，同时持久化 runtime details：

```powershell
$env:KB_LOG_DIR = "<project-runtimeLogs-dir>"
```

不要无意留下只用于一次性 smoke-test 的 helper services。只有当 vector service 仅为临时测试启动，且后续 KB 工作不依赖它时，才停止：

```powershell
& $KbExe vector stop --json
```

如果在调试任务中停止服务，在 runtime log 中记录原因。
