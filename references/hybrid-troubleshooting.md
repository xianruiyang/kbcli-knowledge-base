# Hybrid 故障处理

用于查询失败、后端不可用或旧索引兼容性排查。变量来自 [SKILL.md](../SKILL.md)。先读状态，再处理实际失败项：

```powershell
& $KbExe embedding status --manifest <manifest> --json
& $KbExe vector status --manifest <manifest> --json
& $KbExe index status --manifest <manifest> --json
```

状态结果不足以判断完整性时，再按任务需要执行 `index verify`。只读诊断不自动授权下载模型、重启服务、重新分块或整库重建。

## 目标或模型

优先显式传 `--manifest`；alias 不确定时用 `list` 和 `info --kb <alias>` 核对。

缺少 model binding 时，先检查 resolver 返回的 `$ModelRegistry` 及已知有效登记。对支持该参数的命令显式传 `--model-registry <verified-registry>`，避免空的新登记遮蔽已有配置。确需配置时：

```powershell
& $KbExe embedding bind --manifest <manifest> --model-path <model-dir> --json
```

核对模型、格式、精度、维度和路径，不把本机模型路径写入可迁移 manifest。模型文件缺失或不匹配时恢复对应模型；更换模型不是普通连接故障的修复手段。

## 向量服务或 Qdrant

读取 manifest 中的实际 endpoint。使用部署环境已有的服务管理方式启动 Qdrant；共享 skill 不包含源码仓库的 Docker 管理脚本。Docker/WSL 本身无响应时应先诊断基础服务，不反复重试索引构建。

需要启动本机查询服务且任务允许时：

```powershell
& $KbExe vector serve --manifest <manifest> --strategy query --json
```

无需为一次查询先做性能 benchmark。端口被占用时先识别现有服务与使用者，不直接杀进程；重启共享服务前确认影响。Provider/DLL 问题见 [GPU providers](gpu-providers.md)。

## 旧索引与 warnings

Hybrid 查询成功并 fetch 到来源，证明本次链路可用，不证明整库完整性。当前源码的检查命令结果约定见 [命令参考](command-reference.md)；旧运行时还需查看各自的 `data.valid`、`data.passed` 等字段。

仅 embedding 指纹不匹配时，区分实际模型语义变化与指纹格式升级。模型或维度不同不能以“能返回结果”证明正确；只是旧契约且查询可运行时，可说明未迁移限制后继续使用。不要伪造指纹绕过校验。迁移会重新计算多少向量须在维护任务中评估。

Chunk lookup 缺失、回退 chunks JSONL 的 warning 是正文定位路径变化，不表示 Hybrid 降为 keyword。补建 lookup 留到索引维护范围处理。

索引缺失或 stale 时，报告受影响能力；只有维护已获授权才构建对应索引。向量不可用时可明确选择 keyword 或直接读取来源，但不能将其结果称为 Hybrid。查询与引用要求见 [查询指南](querying.md)。
