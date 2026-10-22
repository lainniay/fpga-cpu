# ex9_2 Topic 1 独立测试

范围: Stable Counter, CSR.TID, `rdcntvl.w`, `rdcntvh.w`, `rdcntid`.

从仓库根目录使用现有 HDL 工具链终端执行:

```sh
make check
make test-ex9-topic1
```

需要 `make`, `/bin/sh`, Icarus Verilog (`iverilog`, `vvp`). `make check` 另外需要 Verilator 和 Yosys. 不需要 LoongArch 交叉编译器, Vivado 或官方测试镜像. Windows 原生 PowerShell 如果没有这些工具, 请使用已有 Linux/WSL/服务器工具链环境.

失败时 testbench 使用 `$fatal(1, ...)`, make 应返回非零退出码. 成功必须出现五组 `[PASS]` 和最后一行:

```text
ALL PASS: ex9 Topic 1 (5/5 cases)
```

## 五组测试

| 组 | 验证内容 |
| --- | --- |
| TID | 复位读零, 32 位编号, CSR 写返回旧值, csrxchg 掩码及零掩码, csrwr 后紧接 rdcntid, rj 目的选择, 紧邻加法/分支/store, 零寄存器 |
| 计数与进位 | 高低半部选择, 低 32 位进位, 快照写回, 紧邻 EXE 前递和隔一条指令的 MEM 前递 |
| 回绕 | 64 位全 1 回绕至零, 连续读高低位 |
| 停顿与访存 | 除法实际阻塞期间持续计数, 乘法依赖, 计数值 store/load 及 load 使用, 写 TID/TCFG 不清零 Stable Counter |
| 清流水线 | 用已有 syscall/ertn 产生真实 flush, 计数器继续递增, 被清掉的读取不写 GPR, 年轻 store 和 TID 写不泄漏 |

## 如何检查

testbench 直接实例化 `mycpu_top`, 使用独立同步 SRAM 模型. 指令编码函数位于 testbench, 四条关键机器码与仓库 `for_test_obj/ex9_obj/test.s` 核对. 程序在模拟 ROM 中构建, 每条正常提交指令的 PC 均与预定执行顺序比较. GPR, CSR 和数据内存使用独立参考状态按指令语义计算结果; 错路径的额外提交、写口或访存会失败. 每组有 5000 个运行周期超时, 并检查指定场景实际出现, 不把未执行的场景算作通过.

Stable Counter 的独立参考值按时钟累计, 在正常、stall、flush 周期均与 DUT 比较. 本分支选择在 ID→EXE 接收沿采样, 测试也在该沿记录参考计数, 再核对最终写回及后续指令使用的值. 这是本分支的采样约定, 不是要求所有 LA32R CPU 在同一级采样.

进位和回绕两组在复位结束后, 于下降沿之后一次性设置 `dut.u_exe_stage.u_counter.stable_counter` 的初值. 这是仅用于仿真的状态注入, 不修改 RTL, 不使用持续 force, 不跳过后续递增检查. 其余三组均从硬件正常复位值运行. 测试读取少量内部握手、WB valid 和前递信号作观察及覆盖检查, 并依赖当前层次名称.

输出只保存在被 Git 忽略的 `build/ex9_topic1/`. 不调用 `select-test.sh`, 不读写 `func/obj`, 不生成或修改 golden, 不修改官方比较逻辑.

可选波形:

```sh
make test-ex9-topic1 VVP_ARGS=+WAVES
```

生成 `build/ex9_topic1/ex9_topic1.vcd`.

本测试不证明定时器中断、软件中断、ex9_1 的异常扩展或完整 ex9 已通过. Topic 1 定向测试通过后, 仍需由操作者执行 `make run TEST=ex8` 回归已有功能; 完整 ex9 留到双方功能合并后验证.

测试文件已编写并作静态核对; 编译、仿真及 `make check` 由操作者运行, 运行结果以实际日志为准.
