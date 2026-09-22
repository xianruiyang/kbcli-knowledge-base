# Embedding 性能调优

仅在配置性能策略、建库耗时优化或排查性能退化时读取。普通查询不必先运行 benchmark。运行时变量见 [SKILL.md](../SKILL.md)。

## 选择范围

- 查询关注单次延迟，使用 `--purpose query`；建库关注吞吐，使用 `--purpose index`。需要两者时才选择 `all`。
- 优先复用有效的本机 profile。provider、device、模型路径和测量结果保存在本机 registry，不写入可迁移 KB manifest。
- 只测实际可用的 provider 和已确认的 device。CPU 可作为基线；GPU 不保证更快，准备条件见 [GPU providers](gpu-providers.md)。
- `--if-missing` 只补缺失的有效策略；主动重测时去掉它。模型、运行时、驱动或文本长度分布变化后，可按性能需要重新测量，不自动重建知识库。

## 执行

先确认绑定与已有 profile：

```powershell
& $KbExe embedding status --manifest <manifest> --json
```

以下以 CPU 建库调优为例。先查看代表样本及候选规模，再在任务允许的成本内执行：

```powershell
& $KbExe embedding optimize --manifest <manifest> --vector-exe $VectorExe --providers cpu --purpose index --quick --dry-run --json
& $KbExe embedding optimize --manifest <manifest> --vector-exe $VectorExe --providers cpu --purpose index --quick --json
```

查询调优将 `index` 换为 `query`。已具备 DirectML 运行时和设备时可使用 `--providers cpu,dml --device-ids <id>`；CUDA 同理。自定义模型登记时传入同一个 `--model-registry <path>`。

Index 调优从当前 KB 向量输入中选取短、中、长代表样本，不对整库推理；读取和分词仍有成本。空库使用标记为 synthetic 的样本。超预算旧 chunks 应在获授权的维护中重新分块。

## 使用与结果

- `skipped=true`：复用了已有 profile，本次未 benchmark。
- `optimization_profile_purposes`：区分已有 query 和 index 策略。
- `strategy.query`：查询路径；`strategy.index_buckets`：按输入长度选择建库 provider/device/batch。
- `benchmark_samples`：说明样本来源，不代表整库必然达到同样吞吐。
- 部分 provider 候选失败并不等于整个优化失败，查看最终可用推荐及 warnings。

交互式服务使用 `vector serve --strategy query`。默认向量构建可使用匹配的 index profile 并管理构建期间所需的服务；只有明确手动启动单个建库服务时才使用 `--strategy index`。仅有 query profile 时，构建使用 manifest endpoint 和默认批量设置。

性能结论以实际工作负载为准。需要验证时复用当前任务的查询或构建结果，不额外发起整库构建。不要停止其他任务共享的服务。
