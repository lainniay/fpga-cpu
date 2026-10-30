# UART 模块测试

使用真实的 `uart_tx.v`、`uart_rx.v` 和 `uart_mmio.v`，没有替代模块。
测试只验证 UART 模块，不包含 CPU、地址桥、板级引脚或实际系统时钟适配。

## 手动运行

在工程根目录的 PowerShell 中执行：

```powershell
wsl bash -lc 'cd /mnt/d/Computer_Organization/fpga-cpu && bash tests/uart_mmio/run.sh'
```

脚本依次编译并运行 TX、已有 RX 回归和 MMIO 测试。
任一步失败立即停止，仿真日志保存在 `build/uart_mmio/`。
创建或修改测试文件本身不代表仿真已经通过，以实际运行输出为准。

## 测试范围

| 部分 | 检查内容 |
| --- | --- |
| TX 独立测试 | 9600/115200 两档、六种数据图案、低位先发、每个位的完整周期、停止位结束前保持 busy、接受沿立即变忙、帧内锁存数据与波特率、忙时请求忽略、复位取消发送 |
| RX 回归 | 两档波特率、输入相位、连续帧、假起始位、错误停止位、帧内改波特率、复位取消接收 |
| MMIO 访问 | sel/commit/字节写使能、所有 16 种写使能取值、全部 256 个精确偏移、只读入口写入无副作用、未选中和空缓冲读零、commit 为零时组合读取 |
| MMIO 发送 | 接受写入同沿开始发送、沿后 TX_READY 清零、只发送低字节、忙时写入丢弃、连续 commit 按每个有效沿解释、真实输出引脚解码 |
| MMIO 接收 | 真实串行输入、缓冲保持和读清除、满缓冲丢新保旧、满/空缓冲下同拍读取和接收、错误帧恢复、全双工、复位优先级及恢复 |

同拍读取测试只观察真实 RX 的公开输出 `rx_valid` 来安排总线访问时刻，
不强制修改 DUT 信号，也不依赖 RX 状态机的实现。
读取结果在访问上升沿、DUT 非阻塞赋值生效前采样，符合接口约定。

## 成功标志

三项测试应分别出现：

```text
[PASS] UART TX complete: 13 frames checked
[PASS] UART RX complete: 23 bytes checked
[PASS] UART MMIO complete: 13 cases, 12 TX frames, 1 reset abort
```

## 波形

编译完成后，可单独重新运行相应测试并添加 `+wave`：

```powershell
wsl bash -lc 'cd /mnt/d/Computer_Organization/fpga-cpu && vvp build/uart_mmio/uart_mmio_tb.vvp +wave'
```

MMIO 波形保存在 `build/uart_mmio/uart_mmio.vcd`。
数字仿真不验证真实引脚电气连接、物理亚稳态或 Vivado 实现时序。
