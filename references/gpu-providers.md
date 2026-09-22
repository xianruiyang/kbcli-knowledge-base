# CPU、DirectML 与 CUDA

用于选择运行时或排查 GPU provider 不可用。调优命令与 profile 语义统一见 [Embedding 性能调优](embedding-optimization.md)。

## 运行时选择

| Provider | 使用条件 |
| --- | --- |
| CPU | 包含 CPU provider 的 ONNX Runtime，可作为性能和兼容性基线 |
| DirectML | Windows 上支持 DirectML 的设备，以及配套的 DirectML-capable ONNX Runtime 和依赖 DLL |
| CUDA | NVIDIA GPU、CUDA-capable ONNX Runtime，以及匹配的 CUDA/cuDNN 依赖 |

使用同一发行包的 EXE 与 DLL，不从其他构建随意拼装，也不替换系统目录中的 DLL。模型路径、provider/device 和 profile 属于本机配置。具体模型及精度须与 KB 的向量语义匹配。

GPU 不一定更快：短查询、短 chunks、批量大小和设备启动成本都会影响结果。只比较实际存在的设备；device 0 未必是希望使用的显卡。不要默认枚举多个不存在的 device。

## 配置与诊断

运行时通过 [SKILL.md](../SKILL.md) 解析。先查看当前绑定和服务：

```powershell
& $KbExe embedding status --manifest <manifest> --json
& $KbExe vector status --manifest <manifest> --json
```

需要比较 CPU 与 DirectML 且当前任务允许调优时：

```powershell
& $KbExe embedding optimize --manifest <manifest> --vector-exe $VectorExe --providers cpu,dml --device-ids <known-device-id> --purpose index --quick --json
```

查询延迟调优使用 `--purpose query`。自定义 registry 时对支持该选项的命令使用一致的 `--model-registry`。

- Provider 不可用：核对发行包是否支持它、依赖 DLL 是否匹配，再决定是否安装或更新依赖。
- 设备不支持：核对适配器与 device id；DirectML 可能报告 `DXGI_ERROR_UNSUPPORTED`。
- 服务仍使用旧配置：运行时文件更新不改变已有进程；先确认服务归属，再安排切换。
- GPU 比 CPU 慢：保留实测更快的策略，无需强制使用 GPU。
- 自动选择发生 CPU fallback：查看 warnings；不把回退后的速度归因于 GPU。

查询可用性排查见 [Hybrid 故障处理](hybrid-troubleshooting.md)。更换 provider 不自动授权换模型、迁移旧向量或重建整库。
