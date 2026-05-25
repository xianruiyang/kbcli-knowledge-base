# Hybrid 故障处理

当 `hybrid` 查询失败、返回 backend errors，或看起来降级到低质量证据时，使用此 reference。

## 判断流程

从三个 status checks 开始。`$KbExe` 和 `$VectorExe` 来自 `SKILL.md` 中描述的随包 Release 运行时。

```powershell
& $KbExe embedding status --manifest <manifest> --json
& $KbExe vector status --manifest <manifest> --json
& $KbExe index status --manifest <manifest> --json
& $KbExe index verify --manifest <manifest> --json
```

然后按第一个失败分支处理。

诊断时不要把低质量 fallback 当成成功。如果用户要求知识库回答而 Hybrid 不可用，要么修复缺失依赖，要么明确报告缺失依赖和恢复 Hybrid 的命令。

## 1. Manifest 或 Target 失败

症状：

- `KB_TARGET_REQUIRED`
- `KB_MANIFEST_NOT_FOUND`
- `KB_MANIFEST_INVALID`
- unexpected alias target

操作：

```powershell
& $KbExe info --manifest <manifest> --json
& $KbExe list --json
```

优先使用显式 `--manifest`。只有 `list` 和 `info --kb <alias>` 证明 target 正确后才使用 alias。

## 2. 缺少 Model Binding

症状：

- `embedding status` 显示 `configured=false`
- search 返回 `KB_MODEL_PATH_NOT_CONFIGURED`

操作：

```powershell
& $KbExe model list --json
& $KbExe embedding bind --manifest <manifest> --model-path <model-dir> --json
& $KbExe embedding status --manifest <manifest> --json
```

如果模型本地不存在，使用项目模型下载路径，或请用户提供模型目录。不要把本地模型路径写入 portable KB manifests。

## 3. Model Files 无效或不匹配

症状：

- model path 存在但 `/v1/embeddings` 失败；
- dimension mismatch；
- tokenizer/model file 缺失。

操作：

```powershell
& $KbExe model verify --path <model-dir> --json
& $KbExe embedding test --manifest <manifest> --json
```

如果 embedding requirements 变化，重建 vector indexes：

```powershell
& $KbExe index build --manifest <manifest> --target vector --json
```

## 4. Vector Service 未运行

症状：

- `vector status` 显示 `available=false`；
- `/health` 返回 connection error 或无数据；
- search 对 `/v1/embeddings` 返回 `KB_HTTP_REQUEST_FAILED`。

操作：

```powershell
& $KbExe embedding optimize --manifest <manifest> --vector-exe $VectorExe --providers cpu --purpose query --quick --if-missing --json
& $KbExe vector serve --manifest <manifest> --strategy query --json
Start-Sleep -Seconds 3
& $KbExe vector status --manifest <manifest> --json
```

如果服务以错误 provider 启动，或 DirectML/CUDA 可用或失败，先使用 `embedding-optimization.md` 和 `gpu-providers.md`，再回到 hybrid queries。除非当前任务是 vector index build 性能，否则保持 query-only 路径。

如果端口被占用或 stale：

```powershell
Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue
Get-Process | Where-Object { $_.ProcessName -like "*kb-vector-service*" }
```

如果本轮仅为 isolated check 启动一次性 helper，且后续 KB 工作不依赖它，只停止该 helper：

```powershell
& $KbExe vector stop --json
```

交互式 KB 使用中，成功查询后不要停止手动启动的 query `kb-vector-service`。除非用户要求关闭、运行进程 stale/wrong，或它只为 isolated smoke test 启动，否则保持运行以支持后续 hybrid queries。`index build` 启动的 build-only managed services 是临时服务，构建后不应残留。

## 5. Qdrant 未运行或 Collection 缺失

症状：

- `qdrant_collection_available=false`；
- Qdrant URL 不可访问；
- vector search 返回 backend unavailable。

操作：

```powershell
kbCli\scripts\qdrant-up.ps1
& $KbExe vector status --manifest <manifest> --json
& $KbExe index status --manifest <manifest> --json
```

连续 KB 查询或 indexing 中保持项目 Qdrant 服务运行。停止条件与 `kb-vector-service` 相同：用户明确要求，或只为临时测试启动。

如果 Docker Desktop 或 WSL 意外终止，记录错误，尽可能检查 Docker/Qdrant logs，并在运行 rebuild 或 cleanup 命令前确认 Qdrant collection 是否完整。Qdrant crash 本身不代表 source docs、chunks、FTS 或 portable KB package 已损坏。

如果 Qdrant 正在运行但 collection 缺失，重建 vector indexes：

```powershell
& $KbExe index build --manifest <manifest> --target vector --json
& $KbExe index verify --manifest <manifest> --json
```

## 6. Index Stale 或缺失

症状：

- `index status` 显示 `chunks.stale`、`docs.stale`、`fts.stale` 或 `vector.stale`；
- FTS unavailable；
- vector collection 存在但 fingerprint 不同。

操作：

```powershell
& $KbExe validate --manifest <manifest> --json
& $KbExe index build --manifest <manifest> --target all --json
& $KbExe index verify --manifest <manifest> --json
& $KbExe index status --manifest <manifest> --json
```

如果 vector dependencies 不可用且用户无法提供，只构建 FTS，并说明 `hybrid` 仍不可用：

```powershell
& $KbExe index build --manifest <manifest> --target fts --json
```

## 7. Alias 或 Production Collection 错误

症状：

- 查询 manifest collection 时 `hybrid` 可用，但 production alias 返回旧结果或缺失结果；
- `index verify --collection <name>` 对 staging 通过，但 regular query service 仍看到旧数据；
- 最近一次 promote 结果变差。

操作：

```powershell
& $KbExe index verify --manifest <manifest> --collection <expected-collection> --json
& $KbExe eval compare --manifest <manifest> --suite smoke --against <baseline.json> --json
```

如果 promote 了错误 collection 且记录了 previous collection：

```powershell
& $KbExe index rollback --manifest <manifest> --alias <alias> --json
```

Rollback 或 promote 后，沿用户将使用的同一 manifest/alias path 运行有代表性的 `--mode hybrid` 查询。

## 8. 查询可运行但结果噪声高

症状：

- 相关 hits 出现但低 rank 噪声很高；
- 重复 template chunks 占主导；
- 精确名称缺失。

操作：

- 用 KB/source language 重写 query，并保留精确技术术语。
- 当 chunk language metadata 存在时，添加 `--language <tag>`。
- 提高 `--candidate-k` 增强 recall，降低 `--top-k` 获取最终证据。
- Metadata 支持时添加 filters。
- 回答前仅 fetch 高置信 hits。

示例：

```powershell
& $KbExe search --manifest <manifest> --query "<source-language query plus exact terms>" --language zh-CN --mode hybrid --top-k 5 --candidate-k 40 --json
& $KbExe fetch --manifest <manifest> --chunk-id <chunk-id> --include-source --include-links --json
```

## 降级策略

只有以下情况才从 `hybrid` 降级：

- 用户无法提供 required model、vector service、Qdrant 或 index rebuild path；
- 任务明确是 exact-only，且 `keyword` 是正确工具；
- 用户要求非 hybrid 模式。

降级时说明缺失要求和恢复 `hybrid` 的命令。
