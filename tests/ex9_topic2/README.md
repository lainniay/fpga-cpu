# ex9_2 Topic 2 独立测试

范围: 定时器配置寄存器(TCFG, 0x41), 定时器当前值寄存器(TVAL, 0x42), 定时中断清除寄存器(TICLR, 0x44), 异常状态寄存器(ESTAT)第11位. 计时器编号寄存器(TID, 0x40)作为独立状态参与回归.

## 使用

先由代码审阅确认 Topic 2 源码完整, 再由操作者在 WSL Ubuntu 运行:

```sh
cd /mnt/d/Computer_Organization/fpga-cpu
make check
make test-ex9-topic2
make test-ex9-topic1
```

需要 make, /bin/sh, iverilog 和 vvp. make check 还需要 Verilator 和 Yosys. 不需要交叉编译器或 Vivado. 编译、仿真和 make check 均由操作者运行; 作者只做静态审阅, 不宣称测试已通过.

目标先编译两个独立 testbench, 然后依次运行 CSR 模块测试和整核测试. 任意检查失败都使用 $fatal(1, ...), make 返回非零. 成功必须同时出现:

```text
ALL PASS: ex9 Topic 2 CSR (5/5 groups, ... checked edges)
ALL PASS: ex9 Topic 2 CPU (retired=... reads=... writes=... stall=... expiry_in_stall=... running_flush=...)
```

仅出现第一行表示 CSR 测试通过, 不代表整核测试通过. 不要把未执行到的组算成通过.

可选波形:

```sh
make test-ex9-topic2 VVP_ARGS=+WAVES
```

输出为 build/ex9_topic2/ex9_topic2_csr.vcd 和 ex9_topic2_cpu.vcd. 该目录已由仓库 build/ 忽略规则覆盖.

## 两层验证

| 层次 | 覆盖内容 |
| --- | --- |
| CSR 第1组 | 复位关闭与停止值, 32位初值和掩码, 禁止写入当前值, 清除寄存器读零, 读使能, TID 独立, 关闭后保持 |
| CSR 第2组 | 单次装入, 精确到期沿, 单次停止, 请求保持, 写零/零掩码/未选中bit0不清除, 写其他CSR及关闭定时器不清除, 有效写1清除 |
| CSR 第3组 | 不清除请求也持续周期重装, 至少三轮, 中途清除, 下一次到期重新置位, 关闭后不再到期 |
| CSR 第4组 | 运行中改初值, 掩码保留启用位, 零掩码写已启用配置也重装, 只改周期位, 关闭同拍不多减一次, 重新开启, 重配置不清请求 |
| CSR 第5组 | 初值0, 到期与清除同拍时到期优先, 到期与重配置同拍时保留旧事件并装入新值, 异常/返回屏蔽软件写而不阻止计数, 其他ESTAT字段隔离, 活动期间复位 |

整核测试直接实例化 mycpu_top, 用本地同步指令 SRAM 执行真实 csrrd/csrwr/csrxchg 指令. 按预定提交PC逐条检查GPR写回、CSR读写端口、写掩码和原始操作数. 检查写CSR返回旧值, 紧邻使用读回值, 软件只读字段, 单次/周期/重新配置. 通过真实除法产生停顿, 要求停顿期间确实发生到期; 通过 syscall 和 ertn 产生两次真实 flush, 检查定时器和 Stable Counter 继续运行, 被清掉的年轻配置/清除指令不产生副作用. 完成前检查覆盖计数, 场景没有执行也会失败.

## 参考依据与时序

依据 ex9_plan.md、课程指导书定时器实现说明, 以及现有 func/inst/n49_ti_ex.S、n51_soft_int_ex.S 和 include/inst_test.h. 官方用例还验证中断入口、上下文恢复和访存副作用, 需要 Topic 3 与队友异常扩展完成, 因此本目标不调用官方 ex9.

本分支选择32位倒计时, 初值为 {TCFG[31:2], 2'b0}. 装入 L 的上升沿后读到 L; 后续 L 个沿后读到0; 再下一个沿处理到期并重装/停止. 单次停止值为 0xffffffff, 配置启用位保留. 软件写配置且新配置启用时重装, 包括有效的零掩码写; 写后关闭时保持剩余值. 到期与清除同拍时到期优先. 判断到期使用沿前的配置和计数, 不因同拍重新配置丢掉旧事件.

timer_reference.sv 用64位绝对到期拍数计算期望剩余值, 不逐拍复制 RTL 减法器. CSR 测试通过公开读端口逐拍比较配置、剩余计数、完整ESTAT、清除寄存器、TID、ERA. 整核测试在比较所有实际CSR访问端口与独立指令译码结果后, 用这些已核对的访问推进计时参考模型. 写回检查读取沿前状态, 状态检查在非阻塞赋值生效后进行. 两个测试均不 force 或改写 DUT 内部状态.

整核测试观察 dut.u_wb_stage.ws_valid、流水级握手、CSR状态与 Stable Counter 作额外检查, 因此依赖当前实例和信号名称. 后续若改变层次名称, 需要相应更新观察路径.

本目标只写 build/ex9_topic2 的仿真产物, 不选择或覆盖官方镜像, 不生成/修改 golden, 不改变 trace 比较逻辑. 原 Makefile 的 clean 不删除独立测试的 build 目录.

本测试不证明 Topic 3 的中断判定、异常编码、入口跳转和中断返回已经实现, 也不证明完整 ex9 已通过. 两个分支合并前仍需运行 ex8 回归及完整 ex9.
