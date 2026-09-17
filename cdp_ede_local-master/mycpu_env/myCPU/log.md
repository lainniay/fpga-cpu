# Ex1

拆分:

```
IF -> ID -> EXE -> MEM -> WB
```

5 个流程, 需要注意 [握手协议](/Users/lainniay/Code/FPGA/cdp_ede_local-master/mycpu_env/myCPU/Protocol.md).

每一个环节的 ready_to_go 都还是 1'b1.

# Ex2

当后面的指令需要用到前面的指令的结果的时候, 可能前面的指令还没有到 WB, 此时, 如果后面的指令在 ID Read Register 的话, 就会读到错误的数据.

因此需要在前面的指令还没有到 WB 的时候, 让后面的指令在 ID Stall. 

显然的是, 这样的话, 会带来性能问题.