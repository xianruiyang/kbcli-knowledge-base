# 使用 kbCli 查询

当需要基于现有 `kb-manifest.json` 知识库回答时，使用此 reference。

命令示例使用 `SKILL.md` 中定义的随包 Release 运行时变量 `$KbExe` 和 `$VectorExe`。

## 目标解析

优先使用显式 manifest path：

```powershell
& $KbExe info --manifest <manifest> --json
```

只有确认 registry alias 解析到预期 manifest 后才使用 alias：

```powershell
& $KbExe list --json
& $KbExe info --kb <alias> --json
```

不要把 `discover` 当作查询热路径。`discover` 仅用于显式 import/install 辅助。

如果 CLI build 可能变化，依赖本文示例前先运行 `commands --json`：

```powershell
& $KbExe commands --json
```

## 查询语言

检索使用知识库 primary/source language。可从 KB skill `SKILL.md`、manifest metadata、topic map、source path、source title，或实际 `content/markdown/` 和 chunks 判断。

如果用户用另一种语言提问，调用 `$KbExe search` 前先把检索意图翻译或改写为 KB/source language。原始技术标识符保持不变：

- API、class、function、module、property、config、command、asset、error code 和 file name；
- 官方产品名和缩写；
- 可能在来源中按原文索引的术语。

多语言 KB 中，如果能提升召回，可同时包含 source-language term 和用户关键术语。优先 source language，再添加原始术语：

```powershell
& $KbExe search --manifest <manifest> --query "<source-language query plus critical original terms>" --mode hybrid --json
```

当 KB 有 language metadata 且 CLI 可用它做 ranking boost 时，使用 `--language <tag>`：

```powershell
& $KbExe search --manifest <manifest> --query "<query>" --language zh-CN --mode hybrid --json
```

此规则只影响检索。最终回答使用用户要求或当前对话语言，除非用户要求其他输出语言。

## Hybrid 优先模式选择

kbCli 查询默认使用 `hybrid`。`hybrid` 结合 SQLite FTS candidates 与 Qdrant vector candidates 并做 fusion；除非用户明确要求其他模式，或环境无法支持，否则它是 source-backed answer 的正常路径。

详细失败处理读取 `hybrid-troubleshooting.md`。首次 embedding 优化和已保存 query profile 读取 `embedding-optimization.md`。DirectML/CUDA 设置或 provider 选择读取 `gpu-providers.md`。`resolve`、`compare`、`search-many`、filters、rerank 或 registry 操作等命令变体读取 `command-reference.md`。

机器状态未知时，检查完整 Hybrid 链路：

```powershell
& $KbExe embedding status --manifest <manifest> --json
& $KbExe vector status --manifest <manifest> --json
& $KbExe index status --manifest <manifest> --json
```

`hybrid` 需要：

- manifest embedding requirement 有本地模型绑定；
- `kb-vector-service` 响应 manifest embedding endpoint，通常是 `http://127.0.0.1:8765/v1/embeddings`；
- Qdrant 可通过 manifest vector backend URL 访问；
- 目标 Qdrant collection 可用；
- vector index state 未 stale。

降级前先准备环境：

- 如果缺少 model binding，请用户提供或绑定本地模型路径：

```powershell
& $KbExe embedding bind --manifest <manifest> --model-path <model-dir> --json
```

- 如果 model 已配置但 vector service 未运行，启动它：

```powershell
& $KbExe embedding optimize --manifest <manifest> --vector-exe $VectorExe --providers cpu --purpose query --quick --if-missing --json
& $KbExe vector serve --manifest <manifest> --strategy query --json
```

当前机器已有 embedding optimization profile 时，`vector serve --manifest <manifest> --strategy query` 可自动选择保存的 provider/device strategy。如果机器还没有 query profile，运行首次 `embedding optimize --purpose query --if-missing`，或显式传入 `--execution-provider` 和 `--device-id`。不要只为回答用户问题运行 `--purpose index` 或 `--purpose all`。只有使用匹配的 provider-capable vector service build 时，才使用 `cpu,dml`、`cpu,cuda` 或 `cpu,dml,cuda`。provider/device 选择保存在本地 model registry，不写入 portable KB manifest。

- 如果 Qdrant 未运行，在可用时启动项目 Qdrant 服务：

```powershell
kbCli\scripts\qdrant-up.ps1
```

交互式 KB 查询会话中，启动后的可复用服务保持运行。不要每次查询后停止 Qdrant 或 `kb-vector-service`。仅在用户要求、运行服务已知 stale/wrong，或服务只为一次性 smoke test 启动且后续 KB 工作不依赖它时停止。

- 如果索引 stale 或缺失，且环境支持 vector indexing，重建：

```powershell
& $KbExe index build --manifest <manifest> --target all --json
```

然后使用 `hybrid` 查询：

```powershell
& $KbExe search --manifest <manifest> --query "<query>" --mode hybrid --json
```

如果省略 `--mode`，CLI 使用 manifest `retrieval.default_mode`。Agent 工作流中，除非刻意测试 manifest default，否则显式传入 `--mode hybrid`，使 shell history、runtime logs 和最终回答可审计实际检索模式。

只有在用户无法提供所需 Hybrid 环境、当前任务明确需要 exact-only lookup，或用户要求其他模式时，才降级。降级时说明缺少哪项要求，以及如何恢复 `hybrid`。

`keyword` 用于精确术语、API、class name、module name、error code 和低资源 fallback：

```powershell
& $KbExe search --manifest <manifest> --query "<query>" --mode keyword --json
```

## 证据 Fetch

Search result 是候选证据，不是最终证明。给出实现建议前，先 fetch 关键 hit：

```powershell
& $KbExe fetch --manifest <manifest> --chunk-id <chunk-id> --include-source --include-links --json
```

回答时引用相关 `chunk_id`、`source_path`，以及 source metadata 中存在的 official URL。

Source-backed answer 使用以下证据循环：

1. 使用 source-language wording 运行一个或多个 Hybrid search。
2. 回答前 fetch 最强 chunks。
3. 以 fetch 到的文本作为证据边界。
4. 区分 KB 证据和自己的推理、实现建议或通用领域知识。
5. 如果重要 claim 不在 fetched chunks 中，要么继续 fetch 证据，要么标注为推断。
6. 如果 KB 无法回答，说明 KB 没有足够证据，并写明使用过的 query/fetch 路径。

多步骤实现回答中，引用支撑核心 claim 的 chunks，不必逐句引用。citation 数据要足够精确，便于另一个 agent 重新 fetch 同一证据。

## 常见失败

- `KB_MODEL_PATH_NOT_CONFIGURED`：绑定或注册本地模型路径，或使用 `keyword`。
- `/v1/embeddings` 或 `/health` 的 `KB_HTTP_REQUEST_FAILED`：启动或修复 `kb-vector-service`。
- Qdrant collection unavailable：启动 Qdrant 并重建或恢复 vector indexes。
- stale vector 或 FTS state：source/chunk/content 变化后运行 `$KbExe index build --target all`。

不要忽略 JSON 输出中的 warnings。Backend warnings 是检索证据状态的一部分。
