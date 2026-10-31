# 分支预测和 UART TX 独立测试

测试仅实例化对应模块，不依赖尚未完成的 ICache、UART RX 或 MMIO。
RTL 按 Verilog 编译，测试平台按 SystemVerilog 编译；时钟均为 100 MHz。

在仓库根目录的 PowerShell 中运行，按本机安装位置指定 Vivado bin 路径：

```powershell
./tests/extensions/run_tests.ps1 -VivadoBin 'E:/Xilinx/Vivado/2023.2/bin'
```

脚本依次运行两个模块，编译失败、仿真错误或缺少最终 PASS 标记都会报错。
仿真日志 `simulate.log` 和波形 `.wdb` 输出到 `tests/extensions/results/<模块名>/`，此目录不纳入版本控制。

## 验证范围

- 分支预测：64 项清空与独立查询、四种计数状态及上下界饱和、同索引不同 tag 替换、两种方向的新项初始化、不跳时目标更新、连续训练、禁用训练、同 PC 查询更新的沿前沿后行为、同步复位优先级、2,000 拍固定种子随机参考模型比较。
- TX：9600/115200 两种速率、起始位和完整停止位、8 位数据低位先发、逐时钟核对每位长度和 busy、发送中输入变化、忙时请求丢弃且不排队、开始/数据/停止阶段同步复位及恢复、16 帧固定种子随机数据。

Vivado 2023.2 的预期结束标记：

```text
PASS tb_branch_predictor checks=4567 time=22786000
PASS tb_uart_tx frames=28 checks=729567 time=7406386000
```

以上 `%t` 数值单位为 ps；结束时间分别为 22,786 ns 和 7,406,386 ns。
测试只通过公开端口判断结果，不依赖实现内部寄存器名称。

这两项测试不代表整机时序收敛或上板通过。IF/ID 的预测纠错、MMIO 接入以及实际板级时钟和引脚仍需合并后联调。
