# 使用 kbCli 查询

变量解析见 [SKILL.md](../SKILL.md)。本页只处理已有知识库查询；服务与索引故障见 [hybrid-troubleshooting.md](hybrid-troubleshooting.md)。

## 定位目标

优先使用显式 manifest。需要使用 alias 时，先核对它指向的库：

```powershell
& $KbExe info --manifest <manifest> --json
& $KbExe list --json
& $KbExe info --kb <alias> --json
```

`discover` 用于扫描指定目录，不是每次查询的前置步骤。

## 检索与取证

使用知识库 primary/source language 组织查询，保留 API、类名、错误码等原始标识符。多语言库可加入相关原文术语；最终回答使用用户语言。

```powershell
& $KbExe search --manifest <manifest> --query "<source-language query>" --mode hybrid --top-k 8 --candidate-k 40 --json
& $KbExe fetch --manifest <manifest> --chunk-id <chunk-id> --include-source --include-links --json
```

Hybrid 合并 FTS 和向量候选。显式写 `--mode hybrid` 可避免 manifest 默认模式不同；省略该参数时以 `retrieval.default_mode` 为准。

- Search 返回候选；重要结论由 fetch 原文支撑。
- 引用 `chunk_id`、`source_path` 和已有来源 URL，不编造来源链接。
- 候选不充分时调整查询或继续取证；没有足够证据时说明缺口。
- 不把源码版本、来源年代或适用范围之外的推断写成 KB 已证事实。

## 改善召回

先核对查询语言和精确术语，再考虑扩大 `--candidate-k` 或调整最终 `--top-k`。支持的过滤参数以当前运行时 `search --help` 为准：

```powershell
& $KbExe search --manifest <manifest> --query "<query>" --mode hybrid --language zh-CN --filter source_type=official_docs --json
& $KbExe resolve --manifest <manifest> --symbol "<exact identifier>" --json
& $KbExe fetch --manifest <manifest> --chunk-id <chunk-id> --neighbors 2 --include-source --include-links --json
```

Filter 值须来自目标库实际 metadata。`fetch --neighbors` 用于读取同文档上下文，不替代核对来源。

## 依赖和降级

Hybrid 需要模型绑定、embedding service、Qdrant collection、FTS 和 chunks。状态未知或实际查询失败时，再按故障处理指南做针对性检查；不要每次查询先运行全部诊断和 benchmark。

只读查询不授权模型下载、修改配置、重建索引或重启共享服务。依赖暂不可用或用户明确选择其他模式时，可以使用 `keyword`、`vector` 或 `structured`，说明实际模式与限制；不能把降级结果称为完整 Hybrid。

```powershell
& $KbExe search --manifest <manifest> --query "<exact terms>" --mode keyword --json
```

Warnings 是结果的一部分。旧索引的指纹校验失败、正文定位回退和真正的后端不可用要分别解释，见故障处理指南。
