# LoongArch CPU local workspace

本目录按 `docs/00_总览/macOS调试与Linux服务器构建指南.md` 准备，用于在 macOS 上编辑、检查和仿真课程 RTL。

## 目录

```text
.
├── .vscode/                 # VS Code 项目设置与任务
├── cdp_ede_local-master/    # 课程工程；CPU 源码在 mycpu_env/myCPU/
├── for_test_obj/            # ex1～ex9 的测试镜像
├── scripts/                 # 测试切换辅助脚本
└── docs/                    # 指南与课程资料
```

## 常用操作

在 VS Code 中打开当前目录，然后：

- `Cmd+Shift+B`：运行 Verilator 和 Yosys 检查；
- `Terminal: Run Task` → `LoongArch: Run selected test`：选择 ex1～ex9，生成参考 trace，并仿真 CPU；
- `Terminal: Run Task` → `LoongArch: Open waveform`：使用 VaporView 打开最近生成的 VCD；
- 命令面板中的 `Verilog: Doctor`：检查 HDL 扩展所看到的工具链。

终端中可以执行等价命令：

```bash
make tools
make check
make run TEST=ex1
```

每次切换测试都会覆盖 `mycpu_env/func/obj/` 中的两个 `.mif`，并重新生成对应的 `golden_trace.txt`。Icarus 功能仿真不替代 Linux 服务器上的 Vivado 综合、实现和 bitstream 生成。
