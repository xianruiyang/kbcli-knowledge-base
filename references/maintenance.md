# 维护与运维

运行时变量见 [SKILL.md](../SKILL.md)。只执行当前任务涉及的内容、索引或服务操作；检查范围见 [知识库质量与验收](quality-definition.md)。

## 内容更新

先确认 manifest、来源与索引状态。常规全流程使用 authoring 中的 pipeline；需要分阶段控制时：

```powershell
& $KbExe source sync --manifest <manifest> --json
& $KbExe ingest --manifest <manifest> --changed-only --json
& $KbExe chunk --manifest <manifest> --changed-only --json
& $KbExe content build --manifest <manifest> --json
& $KbExe index build --manifest <manifest> --target all --json
```

来源暂时不可访问不等于有意删除。确认删除时使用 `source remove --source-id <id>`，再更新派生内容与索引，不手动删除索引行。

向量构建复用输入、元数据和模型身份均匹配的点，只嵌入新增或变化项；替换批次成功后再删除旧点。失败后重跑可复用已写入的点，但不是整个 collection 的原子事务。需要原子发布时使用已有 staging/alias 工作流。

不要为普通更新先运行 `index clean`。模型语义、维度、chunking 或 `embedding_text` policy 变化可能导致大量向量重新计算；policy 变化也需更新 chunks。具体性能取决于当前版本与已有索引格式。

向量依赖不可用且任务允许只更新全文索引时，可用 `--target fts`，明确 vector/hybrid 索引仍旧或不可用。

## 中断与恢复

```powershell
& $KbExe pipeline resume --manifest <manifest> --run-id <run-id> --json
```

使用已有运行记录恢复同一任务；查看其结果、warnings 和失败阶段，不另建重复账本。直接执行的向量构建可重跑同一命令复用已完成点。新版本写锁记录进程身份，可处理同主机已退出进程遗留的锁；不要删除其他活跃任务持有的锁。

## 模型、服务与运行时

绑定、故障处理见 [Hybrid 故障处理](hybrid-troubleshooting.md)，性能策略见 [Embedding 性能调优](embedding-optimization.md)。普通查询使用 `vector serve --strategy query`；手动单服务建库才使用 `--strategy index`。

更新共享 skill 时使用完整配套的运行时包，保留本机有效的模型登记和可回退副本。文件更新不等于正在运行的服务已切换；先确认服务归属与影响，不擅自中断共享服务。旧进程仍需要的文件副本应保留。

更新 skill 不自动触发知识库重建。模型 profile 可能因运行时身份变化失效；需要性能策略时再按调优指南刷新。源代码构建、DLL 组装与性能实验不属于部署端维护流程。

## 打包与恢复

```powershell
& $KbExe package inspect --path <zip-or-dir> --json
& $KbExe export-skill --manifest <manifest> --output <bundle.zip> --profile standard --json
& $KbExe import-skill --path <bundle.zip> --output <new-kb-dir> --alias <alias> --json
```

`--output` 是目标 KB 目录。目标已存在时默认拒绝覆盖；只有确实要替换时使用 `--replace`。导入 alias 会写本机 registry，避免覆盖其他库的登记。

导出会更新源 KB 的 package state/checksums，再复制内容。当前排除锁、指定的临时评测报告及 logs/runtimeLogs；其他 state、索引、脚本和根目录文件仍可能被打包。不要将模型、本机 registry、秘密信息、Qdrant live storage 或开发临时文件放进待分发目录。打包检查不等于敏感信息审查。

备份使用 `backup create`；恢复优先使用新目录的 `backup restore --input <backup.zip> --output <dir>`，保留现有数据。Qdrant 是派生索引，不能代替来源资料备份。

## 交接

说明内容或配置变化、已执行的检查、仍不可用的检索能力及恢复入口即可。普通维护不强制执行全部 eval、audit、package 检查，也不要求再写一份与运行记录重复的日志。
