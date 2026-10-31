# 远程平台方案 A：直连 UART

## 行为

CPU 从 BRAM 执行 LoongArch 汇编，复位后发送一次 `UART OK\r\n`，随后持续逐字节原样回显，包括二进制字节。UART MMIO 基址为 `0x1faf1000`。

- 物理路径：`rxd → UART RX → CPU MMIO → UART TX → txd`
- TX：H18；RX：J20；LVCMOS33，来自远程模板约束。
- 输入时钟：K21，50 MHz；PLL 输出 CPU 50 MHz、timer 100 MHz。
- 串口：115200、8N1、无流控。
- BTN6 高有效复位；上电保持复位约 1.31 ms，再同步释放。
- CPLD 串口读写、外部 SRAM 和 Flash 禁用，数据总线高阻。
- 远程工程把指令 BRAM 缩为 16384 字（64 KiB），以降低布线延迟并满足 50 MHz；本地普通 SoC 仍保留原 1 MiB 配置。

此方案不实现 CPLD UART；网页串口必须连接到直连通道才能看到输出。

## 1. 生成演示固件并仿真

在仓库根目录执行：

```sh
make remote-uart-demo
```

需要 Icarus Verilog、Python 3 和支持 LoongArch32 的 LLVM。可用 `LLVM_BIN` 指定 LLVM bin 目录。

生成物：

```text
cdp_ede_local-master/mycpu_env/func/obj/inst_ram.coe
cdp_ede_local-master/mycpu_env/func/obj/inst_ram.mif
```

注意：此命令覆盖普通 CPU 测试的指令镜像。生成后不要再运行会覆盖镜像的其他测试再构建 bitstream。

仿真检查启动提示、连续发送的 `41 7a 00 ff 55 0d 0a` 的回显、按键复位后再次提示及回显，并检查未使用外设的片选关闭：

```text
PASS: UART banner UART OK
PASS: remote top UART banner, binary echo and reset
```

仿真旁路 PLL，不能替代 PLL、布局布线或真实引脚验证。当前 RX 无 FIFO；以正常波特率回显，不保证任意长期高速突发或主机速率失配时不丢字节。

## 2. 创建 Vivado 工程

将仓库连同生成的 COE 复制到有 Vivado 的机器。在 Vivado Tcl Console 执行（替换绝对路径）：

```tcl
source /path/to/FPGA/cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/run_vivado/create_remote_project.tcl
```

脚本定位自身目录，创建 `project_remote/loongson_remote.xpr`，综合顶层为 `loongson_remote_top`，仅使用远程 XDC 和远程 50 MHz 输入 PLL。当前器件为 `xc7a200tfbg676-1`，需要与目标平台核对。

也可以批处理执行完整构建（在 `run_vivado` 目录）：

```sh
vivado -mode batch -source build_remote.tcl
```

该脚本新建远程工程，运行综合、实现及 bitstream 生成，并在 `project_remote/` 输出时序、DRC、CDC 和资源报告。实现阶段启用了后布线物理优化；重新运行会重建该远程工程，勿在构建进行时重复启动。

使用 GUI 时依次执行 Generate Output Products、Run Synthesis、Run Implementation、Generate Bitstream。确认指令 RAM 初始化引用刚生成的 COE；更换固件后重新生成 RAM 输出并重新综合、实现，不要复用旧 bitstream。

检查 DRC、时序与 CDC 报告，不要降低错误等级强行生成。

已在 `archlain` 的 Vivado 2019.2 Docker 环境中完成一次实际构建，器件为 `xc7a200tfbg676-1`：

```text
WNS = 0.016 ns
WHS = 0.024 ns
All user specified timing constraints are met.
DRC: 0 errors, 32 DSP pipelining warnings
CDC: 全部 Safe/Info，无 Critical/Unsafe/Unknown
Block RAM: 80 / 365
```

预期输出（远端构建目录）：

```text
cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/run_vivado/project_remote/loongson_remote.runs/impl_1/loongson_remote_top.bit
```

本次已取回：

```text
build/remote_uart_demo/final/loongson_remote_top.bit
SHA-256 542d1a1c0982d15f4ec32592d56618ff07d44a58a3ded18262fcd5b38083f01e
```

时序余量很小（约 16 ps），Vivado 版本、器件速度等级或约束变化都可能使结果不同，必须重新检查，不应把该结果当成所有平台的保证。

## 3. 远程演示

1. 上传上述 `.bit` 并启动。
2. 网页串口关闭本地回显，配置 115200、8N1、无流控，打开串口。
3. 按下并释放 BTN6，应该显示 `UART OK`。
4. 发送 `Hello UART!`，应收到相同字符；可用十六进制模式验证 `00 FF 55 AA`。
5. 再次复位，应重新显示启动提示。

固件已固化于 bitstream 内，不需要向网页 BaseRAM/ExtRAM 上传 `.bin`；该功能不会改写内部指令 BRAM。

没有输出不能直接证明平台采用 CPLD 通道，还需检查时钟、复位、串口配置、COE 是否更新及平台实际接线。本次只验证了本地仿真和 Vivado 构建，尚未在远程网页串口上做物理回环测试。
