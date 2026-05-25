# kbCli Embedding 的 GPU Provider 设置

启用、诊断或优化 `kb-vector-service` 的 DirectML 或 CUDA 时，使用此 reference。

随 skill 打包的 Release runtime 应包含 CPU baseline，并可同时包含 DirectML-capable ONNX Runtime 依赖。此 skill 不包含 `kbCli` 源码树，不能从已安装 skill 内编译 DirectML/CUDA binaries。只有当前 runtime package 中包含匹配的 `kb.exe`、`kb-vector-service.exe`、provider DLL 和 required runtime DLLs 时，才使用对应 GPU provider。

## 固定策略

- 优先使用已保存的 `embedding optimize` profile，不在 KB manifest、scripts 或 KB skills 中硬编码 provider。
- 保持 query optimization 与 index optimization 分离。常规 Hybrid 使用运行 `--purpose query`；vector build 运行 `--purpose index`；只有可接受完整 benchmark 时才用 `--purpose all`。
- Provider/device 决策只保存在本地 model registry，通常是所选 `kb.exe` 旁边的 `kb-models.json`。
- 使用单独 DirectML 或 CUDA runtime package，而 model registry 放在随包 runtime 旁边时，对 `embedding status`、`embedding optimize`、`vector status`、`vector serve`、`search` 和 vector index builds 传入同一个 `--model-registry <kb-models.json>`。
- Vector index build 可直接使用已保存 profile。当 profile 匹配当前 provider-capable `kb-vector-service` executable 时，`index build --target vector|all` 会为选中的 bucket provider/device pairs 启动 build-only managed services，并报告 `bucket_usage`。
- 有效 profile 存在后，使用不带 `--execution-provider` 的 `vector serve --manifest <manifest>`。CLI 可为 `--strategy index` 或 `--strategy query` 选择已保存 provider/device。
- 首次 `--if-missing` automation、query/index strategy selection、profile interpretation 和 rerun triggers 见 `embedding-optimization.md`。
- 只有诊断、benchmark，或还没有 profile 时，才显式使用 `--execution-provider`。
- 常规 KB 工作中保持 Qdrant 和 `kb-vector-service` 运行。仅停止一次性 smoke helper、stale/wrong process，或用户明确要求关闭的服务。
- `auto` 是诊断 fallback order，当前顺序为 CUDA、DirectML、CPU。它不能替代目标机器上的 profiling。

官方参考：

- ONNX Runtime DirectML EP：<https://onnxruntime.ai/docs/execution-providers/DirectML-ExecutionProvider.html>
- ONNX Runtime CUDA EP：<https://onnxruntime.ai/docs/execution-providers/CUDA-ExecutionProvider.html>
- DirectML versioning and redistributable：<https://learn.microsoft.com/en-us/windows/ai/directml/dml-version-history>
- Microsoft.AI.DirectML NuGet：<https://www.nuget.org/packages/Microsoft.AI.DirectML/>

## 共享命令

示例使用这些变量：

```powershell
$Manifest = "<manifest>"
$SkillDir = "<path-to-kbcli-knowledge-base-skill>"
$KbCpu = Join-Path $SkillDir "assets\kbcli\win-x64-release\kb.exe"
$VectorCpu = Join-Path $SkillDir "assets\kbcli\win-x64-release\kb-vector-service.exe"
$ModelRegistry = Join-Path (Split-Path $KbCpu -Parent) "kb-models.json"

$ProviderRuntime = "<path-to-provider-capable-kbcli-runtime>"
$KbProvider = Join-Path $ProviderRuntime "kb.exe"
$VectorProvider = Join-Path $ProviderRuntime "kb-vector-service.exe"
```

将 `$KbProvider` 和 `$VectorProvider` 设为正在测试的 provider-capable runtime。`$KbCpu` 保持为随包 Release runtime 的可靠 fallback。
`--providers` 应设置为该 vector service 实际编译支持的 providers，除非你有意测试 failure/fallback 行为。

Provider 工作前确认 manifest 能解析 embedding model：

```powershell
& $KbCpu embedding status --manifest $Manifest --model-registry $ModelRegistry --json
```

如果 model binding 缺失，绑定本地 ONNX model directory：

```powershell
& $KbCpu embedding bind --manifest $Manifest --model-path <model-dir> --model-registry $ModelRegistry --json
```

## DirectML 流程

DirectML 用于具备 DirectX 12 能力的 AMD、Intel、NVIDIA 或 Qualcomm GPU 的 Windows 机器。它是非 NVIDIA Windows 硬件的常规 GPU 路径。

准备 runtime：

1. 先更新 GPU driver。笔记本有 switchable graphics 时优先 OEM driver；OEM package 对 DirectML 太旧时，使用 vendor driver。
2. 确认当前 skill runtime 或外部 runtime package 是 DirectML-capable。Package 必须在同一 runtime directory 中包含 `kb.exe`、`kb-vector-service.exe`、DirectML-capable `onnxruntime.dll`、`onnxruntime_providers_shared.dll`、`DirectML.dll` 和所有 required runtime DLLs。
3. 如果系统 DirectML runtime 太旧或不一致，将 `Microsoft.AI.DirectML` redistributable `DirectML.dll` 放到 provider-capable `kb-vector-service.exe` 旁边。不要替换 `System32` 下的文件。只有 `DirectML.dll` 不足以启用 DML；`onnxruntime.dll` 本身也必须来自 DirectML-capable ONNX Runtime package。
4. 不要修改 `kb-vector-service` 的 DirectML session constraints：DirectML 要求禁用 memory pattern optimization，并使用 sequential session execution。

优化并启动：

```powershell
& $KbProvider embedding optimize --manifest $Manifest --model-registry $ModelRegistry --vector-exe $VectorProvider --providers cpu,dml --device-ids 0,1 --purpose query --quick --json
& $KbProvider vector serve --manifest $Manifest --model-registry $ModelRegistry --strategy query --json
& $KbCpu vector status --manifest $Manifest --model-registry $ModelRegistry --json
```

如果有多个 display adapters 或 virtual display drivers，benchmark `--device-ids 0,1,2`，让 saved profile 选择。`device_id 0` 是默认 adapter，不一定最快。

## CUDA 流程

CUDA 只用于 NVIDIA 机器。AMD 和 Intel GPU 不能使用 CUDA；使用 DirectML 或 CPU。

准备 runtime：

1. 确认 NVIDIA driver 可见：

```powershell
nvidia-smi
```

2. 安装与 provider-capable kbCli runtime package 兼容的 CUDA/cuDNN runtime，并让 runtime DLLs 在 `PATH` 上可见。
3. 使用 skill 外提供的 CUDA-capable kbCli runtime package。Package 必须在同一 runtime directory 中包含 `kb.exe`、`kb-vector-service.exe`、ONNX Runtime CUDA provider DLLs 和所有 required runtime DLLs。

优化并启动：

```powershell
& $KbProvider embedding optimize --manifest $Manifest --model-registry $ModelRegistry --vector-exe $VectorProvider --providers cpu,cuda --device-ids 0 --purpose query --quick --json
& $KbProvider vector serve --manifest $Manifest --model-registry $ModelRegistry --strategy query --json
& $KbCpu vector status --manifest $Manifest --model-registry $ModelRegistry --json
```

如果未来 binary 包含多个 GPU providers，benchmark 所有可用 providers：

```powershell
& $KbProvider embedding optimize --manifest $Manifest --model-registry $ModelRegistry --vector-exe $VectorProvider --providers cpu,dml,cuda --device-ids 0,1 --purpose query --quick --json
```

## 优化 Profile

以下情况运行优化：

- 机器首次使用；
- GPU drivers 变化后；
- `DirectML.dll`、CUDA、cuDNN 或 ONNX Runtime packages 变化后；
- embedding model 或 precision 变化后；
- 重建或替换 `kb-vector-service.exe` 后；
- 文本长度分布变化到可能影响 index/query batch 选择时。

先跑短首次流程，机器空闲时再跑更完整流程：

```powershell
& $KbProvider embedding optimize --manifest $Manifest --model-registry $ModelRegistry --vector-exe $VectorProvider --providers cpu,dml,cuda --device-ids 0,1 --purpose query --quick --json
& $KbProvider embedding optimize --manifest $Manifest --model-registry $ModelRegistry --vector-exe $VectorProvider --providers cpu,dml,cuda --device-ids 0,1 --purpose index --rounds 3 --json
```

首次自动化使用 `--if-missing`，以复用已有有效 profile：

```powershell
& $KbProvider embedding optimize --manifest $Manifest --model-registry $ModelRegistry --vector-exe $VectorProvider --providers cpu,dml,cuda --device-ids 0,1 --purpose query --quick --if-missing --json
```

优化后，检查 `embedding status` 是否报告 active profile，并检查 `vector serve --manifest --strategy query` 或 `--strategy index` 是否输出 `optimization_profile` object。

## 故障处理

- DirectML provider missing：确认 `$ProviderRuntime` 是 DirectML-capable runtime package，且 DirectML-capable `onnxruntime.dll`、`onnxruntime_providers_shared.dll` 和 `DirectML.dll` 位于 `kb-vector-service.exe` 旁边。
- `DXGI_ERROR_UNSUPPORTED`：所选 adapter 或 runtime 不支持所需 DirectML feature level。更新 GPU driver，尝试另一个 `--device-id`，并在 OS copy 太旧时使用 app-local `DirectML.dll`。
- DirectML 比 CPU 慢：optimization 选择 CPU 时保留该结果。小 query workload 可能 CPU 更快，因为 GPU setup 和 copy cost 占比高。
- CUDA provider missing：确认 `$ProviderRuntime` 是 CUDA-capable runtime package，且 `onnxruntime_providers_cuda.dll` 位于 vector service 旁边。
- CUDA load failure：检查 NVIDIA driver、`nvidia-smi`、CUDA/cuDNN major-version 兼容性和 `PATH`。
- AMD/Intel 上的 CUDA：不支持。使用 DirectML 或 CPU。
- 不同 build directory 选择不同 registry：显式传 `--model-registry` 并重新运行 `embedding status`。
- 手动 `--execution-provider auto` 可用但 saved serve 选择 CPU：重跑 `embedding optimize`；持久化 profile 可能正确地为该 workload 偏好 CPU。

## 验证

Provider 设置后的最低验证：

```powershell
& $KbCpu embedding status --manifest $Manifest --model-registry $ModelRegistry --json
& $KbCpu vector status --manifest $Manifest --model-registry $ModelRegistry --json
& $KbCpu embedding test --manifest $Manifest --model-registry $ModelRegistry --json
& $KbCpu search --manifest $Manifest --model-registry $ModelRegistry --query "<source-language query>" --mode hybrid --top-k 5 --json
```

Index-building 验证只在用户要求维护或 index state stale 时重建 vector indexes：

```powershell
& $KbProvider index build --manifest $Manifest --model-registry $ModelRegistry --target vector --json
& $KbCpu index status --manifest $Manifest --json
```
