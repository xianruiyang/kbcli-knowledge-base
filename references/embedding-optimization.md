# Embedding 自动优化

当某台机器首次使用 kbCli 知识库、用户明确要求优化 embedding，或模型、runtime、driver、binary 更新后检索/建库性能变化时，使用此 reference。

使用 `SKILL.md` 中的随包 Release 运行时变量。随包运行时应保证 CPU baseline 可用；如果同一 runtime directory 内包含 DirectML-capable `onnxruntime.dll`、`onnxruntime_providers_shared.dll` 和 `DirectML.dll`，也可以直接测量 `dml`。CUDA 仍只在提供 CUDA-capable runtime package 和匹配 CUDA/cuDNN 依赖时使用。

## 策略

- embedding provider/device/batch 选择优先使用已保存的 per-machine optimization profile。
- 不要把 provider、device id、benchmark results 或 host-specific paths 写入 portable `kb-manifest.json` 或 KB skill bundle。
- 将 query optimization 与 index/build optimization 分开。Query optimization 必须快速，只 benchmark query workloads；index optimization 可以花更多时间 benchmark chunk-length buckets。
- 首次 query session 使用 `embedding optimize --purpose query --if-missing`，避免正常知识库使用时 benchmark 完整 index matrix。
- 将要构建或重建 vector indexes 的机器，使用 `embedding optimize --purpose index` 或 `--purpose all`。
- 首次自动化使用 `--if-missing`，避免普通查询每次重跑 benchmark。Skip check 是 purpose-aware：query-only profile 不满足 index optimization request。
- 交互式 hybrid/vector 查询启动 vector service 时使用 `--strategy query`。
- `index build --target vector|all` 默认使用已保存 index buckets。当 profile 匹配当前 `kb-vector-service` executable 时，它可为 bucket provider/device pairs 启动短生命周期 managed vector services。
- 本机 embedding transport 默认 `auto`：长期运行的 manifest endpoint 优先 Windows shared memory，失败时使用二进制 embedding 响应，再失败才回退 JSON。需要强制排查时可设置 `KB_EMBEDDING_TRANSPORT=shared_memory|binary|json|auto`。不要为远程 endpoint 使用 shared memory。
- Vector index build 默认尝试 direct upsert：`kb` 将文本和 point payload 发给 `kb-vector-service`，由服务端 embedding 后直接写 Qdrant，避免把 1024 维向量返回给 `kb` 再二次 JSON upsert。需要强制关闭时设置 `KB_EMBEDDING_DIRECT_UPSERT=false`。CLI 自己拉起的短生命周期 managed build endpoint 会跳过 direct-upsert/shared-memory/binary 快路径，使用 JSON embedding response 并由 CLI 端写入 Qdrant，以避免 Windows Release 下的短生命周期服务崩溃和残留进程。
- 只有有意为 vector index build 或 rebuild 手动启动单个 vector service 时，才使用 `--strategy index`。
- 将文本长度视为优化策略的一部分。Query、short chunks、medium chunks 和 long chunks 可能偏好不同 batch size。
- 为后续 KB 工作保留可用的 `kb-vector-service` 和 Qdrant；不要每次查询后停止。

ONNX Runtime 通过 execution providers 使用不同硬件，provider priority/fallback 取决于 runtime package 和可用依赖。本地 profile 存在的原因是最佳路径与机器和 workload 相关。

官方参考：<https://onnxruntime.ai/docs/execution-providers/>

## 首次运行流程

设置常用路径：

```powershell
$Manifest = "<manifest>"
$SkillDir = "<path-to-kbcli-knowledge-base-skill>"
$KbExe = Join-Path $SkillDir "assets\kbcli\win-x64-release\kb.exe"
$VectorExe = Join-Path $SkillDir "assets\kbcli\win-x64-release\kb-vector-service.exe"
```

检查 model binding 和 profile state：

```powershell
& $KbExe embedding status --manifest $Manifest --json
```

如果模型未绑定，先绑定本地模型路径：

```powershell
& $KbExe embedding bind --manifest $Manifest --model-path <model-dir> --json
```

只有当前 host/model/vector-service fingerprint 没有可用 profile 时，才创建 query profile。这是交互式 Hybrid search 的快速首次路径：

```powershell
& $KbExe embedding optimize --manifest $Manifest --vector-exe $VectorExe --providers cpu --purpose query --quick --if-missing --json
```

用户仅查询时不运行完整 index matrix。Query first-run 应优化 `strategy.query` 并启动 `vector serve --strategy query`；index buckets 可稍后添加，不会丢失 query recommendation。

同一机器要构建 vector indexes 时，单独添加 index profile：

```powershell
& $KbExe embedding optimize --manifest $Manifest --vector-exe $VectorExe --providers cpu --purpose index --quick --if-missing --json
```

Quick index mode 会 benchmark 多个 chunk text-length buckets，当前覆盖 short、medium、long、xlong（约 128/512/1024/1536 tokens）和对应 batch size。它适合作为首次建库默认值；full pass 能提供更稳定的长文本覆盖。

有 DirectML 或 CUDA-capable build 时，使用 provider-capable `kb.exe` 和 `kb-vector-service.exe`；DirectML runtime 需要 DirectML-capable ONNX Runtime DLL 与 `DirectML.dll` 同目录。若 model registry 放在另一个 build 旁边，传入同一个 registry：

```powershell
& <provider-kb.exe> embedding optimize --manifest $Manifest --model-registry <kb-models.json> --vector-exe <provider-kb-vector-service.exe> --providers cpu,dml,cuda --device-ids 0,1 --purpose query --quick --if-missing --json
```

查询工作启动：

```powershell
& $KbExe vector serve --manifest $Manifest --strategy query --json
```

建索引工作启动：

```powershell
& $KbExe vector serve --manifest $Manifest --strategy index --json
```

## 主动优化流程

用户要求优化、机器状态变化，或已保存 profile 可能 stale 时，使用 active optimization。此时不要使用 `--if-missing`。

交互式查询的 quick pass：

```powershell
& $KbExe embedding optimize --manifest $Manifest --vector-exe $VectorExe --providers cpu --purpose query --quick --json
```

机器将构建 vector indexes 时的 index pass：

```powershell
& $KbExe embedding optimize --manifest $Manifest --vector-exe $VectorExe --providers cpu --purpose index --quick --json
```

机器可接受较长 benchmark 时的完整 query/index pass：

```powershell
& $KbExe embedding optimize --manifest $Manifest --vector-exe $VectorExe --providers cpu --purpose all --rounds 3 --json
```

Full pass 会扩展 text-length matrix，适合会构建大型 vector indexes 的机器作为长期 profile。

按 binary 和环境选择 provider list：

- 仅 CPU build：`--providers cpu`
- DirectML build：`--providers cpu,dml`
- CUDA build：`--providers cpu,cuda`
- multi-provider build：`--providers cpu,dml,cuda`

GPU provider 设置和失败处理见 `gpu-providers.md`。

## 重跑触发条件

以下情况后重跑 `embedding optimize`：

- 新机器首次使用；
- GPU driver、DirectML、CUDA、cuDNN 或 ONNX Runtime package 变化；
- embedding model、precision、dimension 或 tokenizer 变化；
- `kb-vector-service.exe` 重建或替换；
- 在 CPU、DirectML、CUDA 或 multi-provider build outputs 之间切换；
- 预期 query/index 文本长度分布发生较大变化；
- 明显 latency regression 或意外 provider fallback。

## 结果解读

用 JSON 结果确认：

- `skipped=true` 表示 `--if-missing` 找到有效 profile，未 benchmark。
- `purpose=query` 只 benchmark query workloads，并更新/保留 `strategy.query`。
- `purpose=index` benchmark chunk workloads，并更新/保留 `strategy.index_buckets[]`。
- `purpose=all` 同时重建 query 和 index strategy recommendations。
- `embedding status` 报告 `optimization_profile_purposes.query` 和 `.index`，agent 可判断 profile 是 query-only、index-only 还是完整。
- `strategy.query` 是 query latency 推荐的 provider/device path。
- `strategy.default` 是 fallback provider/device path；可用时从 medium index workload 选择。
- `strategy.index_buckets[]` 按文本长度排序，是优先 index strategy。Vector index build 会估算每个 chunk 的 token count，按长度分组，避免一次 embedding request 跨 bucket boundary，并选择 `max_estimated_tokens` 覆盖该 chunk 的最小 bucket。长于最大已测 bucket 的文本使用最大 bucket 的 recommendation。
- Vector index build 期间，`kb` 可为 bucket provider/device pairs 启动 managed build-only vector services。当前唯一 build mode 是默认 `bucket`：按文本长度 bucket 顺序批量处理，并使用 profile 中该 bucket 的最佳 provider/device 与 batch size。Build 输出报告 `vector.build.build_mode`、`optimized_services_used`、`managed_services` 和 `bucket_usage`。
- Direct upsert 只影响 vector index build，不影响 query search。Build 输出中的 `direct_upsert_batches` 和 `direct_upsert_items` 大于 0 表示已使用该路径。
- `KB_EMBEDDING_TRANSPORT` 只影响 `kb` 调用长期运行 manifest endpoint 取 embedding 的传输方式，不改变模型、provider、batch 策略或 Qdrant payload。`shared_memory` 使用本机 Windows file mapping 传回 f32 little-endian embedding buffer；`binary` 使用 `application/vnd.kb.embeddings.f32le` HTTP body；`json` 使用兼容旧路径的 `data[].embedding`。Direct upsert 成功时不会走这些返回向量路径；短生命周期 managed build endpoint 固定使用 JSON response 和 CLI 端 upsert。
- 如果只有 query profile，vector index build 会回退到 manifest endpoint 和 manifest/default batch size，直到运行过 `--purpose index` 或 `--purpose all`。
- candidate results 中的 provider failures 是诊断数据；只要另一个 provider 成功，不一定是任务失败。

优化后，`embedding status --manifest <manifest> --json` 应显示 active profile。Profile 可用时，`vector serve --manifest <manifest> --strategy query --json` 或 `--strategy index` 应报告 `optimization_profile` object。

## 验证

Query profile 验证：

```powershell
& $KbExe vector serve --manifest $Manifest --strategy query --json
& $KbExe vector status --manifest $Manifest --json
& $KbExe embedding test --manifest $Manifest --json
& $KbExe search --manifest $Manifest --query "<source-language query>" --mode hybrid --top-k 5 --json
```

Index profile 验证：

```powershell
& $KbExe index build --manifest $Manifest --target vector --json
& $KbExe index status --manifest $Manifest --json
```

Transport smoke：

```powershell
$env:KB_EMBEDDING_DIRECT_UPSERT = "true"
& $KbExe index build --manifest $Manifest --target vector --json
$env:KB_EMBEDDING_TRANSPORT = "shared_memory"
& $KbExe index build --manifest $Manifest --target vector --json
$env:KB_EMBEDDING_TRANSPORT = "binary"
& $KbExe search --manifest $Manifest --query "<source-language query>" --mode vector --top-k 3 --json
$env:KB_EMBEDDING_TRANSPORT = "json"
& $KbExe search --manifest $Manifest --query "<source-language query>" --mode vector --top-k 3 --json
Remove-Item Env:\KB_EMBEDDING_DIRECT_UPSERT -ErrorAction SilentlyContinue
Remove-Item Env:\KB_EMBEDDING_TRANSPORT -ErrorAction SilentlyContinue
```

只有需要强制旧的单 manifest endpoint 路径时，才在 `index build` 上使用 `--no-optimized-vector-services`。该模式下先手动启动服务：

```powershell
& $KbExe vector serve --manifest $Manifest --strategy index --json
& $KbExe index build --manifest $Manifest --target vector --no-optimized-vector-services --json
```

仅停止为 isolated smoke test 启动、且后续 KB 工作不需要的服务。
