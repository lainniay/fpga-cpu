# ex9_2 Topic 3 独立中断测试

范围: 异常配置寄存器(ECFG)的局部中断允许位, 当前模式信息寄存器(CRMD)的全局中断允许位, 异常状态寄存器(ESTAT)的软件/定时器请求, ID选择指令并附上中断标志, CSR状态更新等待, WB上报与异常返回, 被取消指令和年轻指令的副作用屏蔽.

## 运行

在WSL Ubuntu终端, 由操作者执行:

```sh
cd /mnt/d/Computer_Organization/fpga-cpu
make check
make test-ex9-topic3
```

目标使用Icarus Verilog, 需要make、/bin/sh、iverilog和vvp. make check还需要Verilator和Yosys. 不需要交叉编译器、Vivado或官方测试镜像. 作者只作静态审阅, 编译和仿真由操作者运行, 不宣称已经通过.

成功必须出现18条按编号输出的[PASS], 以及最后一行:

```text
ALL PASS: ex9 Topic 3 (18/18 cases; CSR waits=... MEM/WB blocked memory=.../...)
```

任意不匹配、未达到覆盖条件或超时都使用$fatal(1, ...), make返回非零. 每例限6000个有效运行周期, 另有全局超时. 只完成部分用例不能视为Topic 3通过.

可选波形:

```sh
make test-ex9-topic3 VVP_ARGS=+WAVES
```

生成build/ex9_topic3/ex9_topic3.vcd, 内含各例复位后的波形. build目录由仓库忽略规则覆盖. 当前clean目标不删除这些独立测试产物.

## 18个用例

| 编号 | 目的 |
| --- | --- |
| 0 | ECFG复位/全宽及部分掩码/零掩码/bit10保留位, 全局关闭、局部关闭、只允许没有请求的来源时不进入中断 |
| 1~9 | 软件中断0、软件中断1、两个软件请求同时有效; 分别取消ADD、LOAD、STORE、CSR写、DIV、MUL、分支、SYSCALL、ERTN; 覆盖开启全局允许、开启局部允许、写请求三种触发顺序 |
| 10~11 | 单次定时器请求在EXE执行更老的正常除法期间置起; 周期定时器至少三轮重装并实际处理/返回三次 |
| 12~14 | 初值0定时器的请求与已经接收的更老CRMD关闭、ECFG关闭、TICLR清除操作重叠, ID必须等旧操作生效, 不能多报中断 |
| 15~17 | 更老SYSCALL在MEM/WB分别屏蔽未标记的年轻store; ERTN恢复PLV3和全局允许后标记返回位置指令; 当前ADD缺少更老LOAD结果时, 被中断取消的ADD不必等该GPR值 |

默认处理程序读取CRMD、PRMD、ESTAT、ERA, 由指令解释器核对值, 清除软件和定时器请求, 然后直接ERTN. 它不修改ERA, 所以被取消的普通指令返回后要重新执行, 正常store只允许发生一次. 用例8和9为了单独检验中断优先于同一条指令的SYSCALL/ERTN, 由处理程序显式把ERA加4, 跳过该条原操作; 用例15也由软件加4跳过已经处理的SYSCALL. 硬件始终必须先保存原指令自身PC, 测试在软件修改前检查它, 不允许硬件自动加4.

测试处理程序保留r23~r28作专用测试寄存器, 主程序不使用它们保存普通工作数据. 用例16的用户态路径不执行CSR指令. 软件请求和定时器均通过真实指令设置, 不使用force或DUT内部状态写入.

## 如何防止假通过

- 程序来自本地模拟ROM, 独立指令解释器维护GPR、CSR、内存和下一条应提交PC. 每条有效WB指令都必须匹配下一PC及指令语义, 包括中断取消、不写GPR/普通CSR、返回旧值和分支路径.
- ID接收时的期望中断决定来自参考CSR状态和独立记录的前序指令, 不读取DUT的ex_int作为答案. 参考级按握手记录EXE/MEM/WB的PC与中断标志, 逐级比较, 丢失或错配标志立即失败. 测试明确采用本分支的ID→EXE接收沿采样方案.
- CSR软件写口逐条核对编号、掩码和原GPR写数据后, 推进Topic 2的绝对到期拍数参考模型. 每拍核对完整CRMD、PRMD、ECFG、ESTAT、ERA、EENTRY、TID、TCFG、TVAL与has_int, 并检查Stable Counter在stall/flush期间持续递增.
- SRAM请求在EXE发出当拍检查, 不只检查最后GPR或RAM. 被标记的load/store不得请求, 更老MEM重定向与WB清空期间年轻访存不得请求. 有效请求必须有正确地址、数据和写掩码, 最终请求数还必须等于正常提交的访存次数.
- 用例数、中断/SYS/ERTN次数、前序CSR等待、请求与状态更新重叠、除法/GPR等待、中断返回以及MEM/WB两拍访存禁止均有覆盖要求. 用例15特意使用未标记的年轻store, 防止只靠年轻指令自身也被标记而掩盖两拍屏蔽逻辑缺失.

## 边界

依据ex9_plan.md、课程指导书第6.2/6.3/6.5节, 以及仓库n49_ti_ex.S、n51_soft_int_ex.S、include/inst_test.h和start.S中断处理约定设计. 本目标不运行select-test.sh, 不覆盖func/obj或for_test_obj, 不生成/修改golden, 不改变官方trace比较逻辑.

本测试观察当前模块层次与少量内部valid、PC、中断标志、握手和CSR状态. 若将来改变信号名或选择另一种合法的中断采样级, 必须调整观察逻辑和该方案的时序约定, 不能据此宣称其他架构实现错误.

本次没有新增硬中断顶层接口, 外部硬中断/核间中断没有被驱动. 不覆盖队友负责的break、INE、ADEF、ALE、BADV及合并后的跨异常全部优先级. 源码静态检查和此目标通过后, 仍需由操作者回归Topic 1、Topic 2和ex8; 双方合并后验证完整ex9及平台硬中断接线.

```sh
make test-ex9-topic1
make test-ex9-topic2
make run TEST=ex8
```
