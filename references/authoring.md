# 创建知识库

用于新建 KB 或导入来源。运行时变量见 [SKILL.md](../SKILL.md)，验收范围见 [知识库质量与验收](quality-definition.md)。

## 初始化与配置

```powershell
& $KbExe init --kb-id <stable-id> --name "<display-name>" --output <kb-dir> --json
```

初始化只创建骨架，尚未生成可查询内容。检查生成的 manifest，按知识库需要设置来源语言、领域与权威来源策略、chunking、embedding 模型和向量后端。只有使用 staging 发布时才需要相应 alias 配置。

具体 KB 的 SKILL.md 说明资料范围、版本、检索语言和来源优先级，并引用共享 `kbcli-knowledge-base` skill。无需在每个 KB 中复制运行时或整套操作指南。

从实际加载的两个 skill 路径解析运行时和 manifest，不猜测当前工作目录，也不假定初始化会生成额外的 resolver bridge：

```powershell
$KbSkillFile = "<loaded KB SKILL.md full path>"
$SharedSkillFile = "<loaded kbcli-knowledge-base SKILL.md full path>"
$Manifest = Join-Path (Split-Path -Parent $KbSkillFile) "kb-manifest.json"
$Runtime = & (Join-Path (Split-Path -Parent $SharedSkillFile) "scripts\resolve-kbcli.ps1") | ConvertFrom-Json
$KbExe = $Runtime.kb_exe
$VectorExe = $Runtime.vector_exe
```

查询示例和证据获取直接引用 [查询指南](querying.md)。主题导航、独立阅读指南与评测问题按实际使用需要补充，不要求为每个 KB 创建相同的附加文件。

## 来源准备

```powershell
& $KbExe source add --manifest $Manifest --type markdown --path <source-path> --title "<title>" --json
& $KbExe source list --manifest $Manifest --json
```

其他来源类型和参数查看当前 CLI help。默认把资料放在 KB 内并使用相对路径；只有明确允许外部路径时使用 `root_policy.allow_external_paths`。不要将生成的 content、indexes、state、日志或模型目录再次导入为来源。

保留可重建的来源和出处。转换、清理或去重若改变内容，应保留必要的转换说明与限制；不要把 Markdown mirror 作为唯一来源。排除规则依据实际生成物设置，不统一排除可能包含正文的 README.md 或 index.md。

图片、表格及媒体应保留理解证据所需的信息。格式和压缩由内容决定，不强制转 JPEG 或丢弃透明度；向量输入折叠链接、媒体路径不代表可读正文也应删除它们。

## 构建

常规端到端建库使用已有 pipeline；先查看计划及当前运行时参数：

```powershell
& $KbExe pipeline plan --manifest $Manifest --recipe local-docs --target all --json
& $KbExe pipeline run --manifest $Manifest --recipe local-docs --target all --vector-exe $VectorExe --json
```

Pipeline 执行配方定义的阶段并保存运行记录。只需局部更新时，使用 [维护指南](maintenance.md) 中的分阶段命令，无需重复完整 pipeline。

构建向量前需要模型绑定和可用的向量后端。绑定 tokenizer 后的 chunking 使用真实 token 预算，并为标题、来源等输入前缀预留空间；离线估算或旧版超预算 chunks 可能需要重新分块。正文 `text` 用于阅读，`embedding_text` 是派生向量输入。

首次调优并非查询或建库的固定前置步骤；有性能需求再读 [Embedding 性能调优](embedding-optimization.md)。

## 交付

按任务需要确认来源可追溯、目标检索模式可用及 fetch 能取回正文，说明未构建或不可用的索引。已有 pipeline 检查结果可直接引用，不机械重复执行。

导出与可迁移内容边界见 [维护指南](maintenance.md)。分享前检查实际文件清单：导出不是敏感信息清理器，KB 根目录内的开发文件和本机状态可能随包带出。
