# Ex1

拆分:

```
IF -> ID -> EXE -> MEM -> WB
```

5 个流程, 需要注意 [握手协议](file:///Users/lainniay/Code/FPGA/cdp_ede_local-master/mycpu_env/myCPU/Protocol.md).

每一个环节的 ready_to_go 都还是 1'b1.

# Ex2

当后面的指令需要用到前面的指令的结果的时候, 可能前面的指令还没有到 WB, 此时, 如果后面的指令在 ID Read Register 的话, 就会读到错误的数据.

因此需要在前面的指令还没有到 WB 的时候, 让后面的指令在 ID Stall. 显然的是, 这样的话, 会带来性能问题.

具体而言, 在 ID 阶段需要检查, EXE, MEM, WB 的指令需不需要写 Regfile, ID 是不是需要读取 Regfile, 以及, 写的目标是不是 ID 需要读的 Reg.

因此, 这样的设计, 只是在 ID 阶段的指令, 明确和 EXE, MEM, WB 阶段冲突的时候, 才会进行回传, 不会破坏正常的五级流水线.

# Ex3 

由于 Ex2 会导致无论是什么指令, 都只会在 WB 阶段写回, 但是实际上部分指令已经在 EXE, MEM 阶段就已经完成计算, 可以进行写回了, 因此, Ex3 做的事情就是使用 EXE, MEM 里面比较新的数据, 替换 WB 中比较旧的数据.

并且优先级是 EXE > MEM > WB, 因为, 前面指令写的数据会被后面的指令覆盖.

由于大部分指令在 EXE 阶段其实就已经算完了, 因此, 直接从 EXE 回传问题不大, 但是 Load 类指令不行, 如果 Load 类指令还在 EXE 阶段, 那么他的真实数据需要在 MEM 才能得到, 此时无法进行回传, 因此 ID 只能阻塞等待, Load 指令到 MEM 阶段进行回传.

> load 类, 是通过 ID 阶段解析出的 res_from_mem 信号进行控制, 并且 res_from_mem 会沿着流水线传递.