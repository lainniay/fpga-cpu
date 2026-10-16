# Address Space

采用了统一地址空间的风格, 但是 Inst MEM 和 Data MEM 并不是同一块, 因此可以同时访问.

真正决定去向的是端口而不是地址, inst_sram 永远进 Inst MEM, data_sram 永远进 Data MEM 和 confreg, 地址高位会被丢弃, 所以存在别名, 比如 0x00000000 与 0x1c000000 在指令侧指向同一个字.

Data 侧还有第三个落点, confreg 位于 0x1faf0000, 掩码 0x1fff0000, 因此 0xbfaf.... 也会命中, 测试程序正是写 0xbfafff10 来报告结束.

## Memory Type

两块 Mem 都是 BRAM. BRAM 是同步的, 读延迟 1 拍, 但吞吐是 1 拍/周期, 数据晚到一拍却从不缺席, 所以流水线不需要为访存加 stall, 只需要把请求那一拍的身份一起寄存下来: IF 用 fs_pc <= next_pc 与 inst_sram_rdata 配对, 访存则在 EXE 级就发出 data_sram_*, 指令走到 MEM 时 data_sram_rdata 正好有效, 于是 IF 与 MEM 的 ready_go 恒为 1.

en 是片选, we 是 4 位字节写使能, 两者独立, 写内存时 en 必须同时拉高, 否则仿真会写而真实 IP 不会写. en 为 0 时 rdata 保持而不是清零, reset 也不清 BRAM, .mif 未覆盖的区域是 X.

地址低 2 位会被丢弃, 非对齐访问会被静默对齐而不报错, ALE 需要自己实现.

sync_ram.v 与 Vivado IP 还有两处不一致, 仿真里写不看 en, 且等价于 READ_FIRST, 而 IP 配置是 WRITE_FIRST, 同拍读写同址会返回新数据, 只要遵守写时 en 拉高并且不同拍读写同址, 就不会踩到.

> Data 侧其实只有两个从设备, bridge_1x2 用 (addr & 0x1fff0000) == 0x1faf0000 分出 confreg, 其余全部落到 data_ram.
> confreg 是一个 64KB 窗口且高位不参与比较, 所以 0xbfaf.... 也命中, 窗口内再由 conf_addr[15:0] 译码到 LED, 数码管, 开关, 按键, timer, cr0~cr7, 以及只给仿真用的 open_trace, num_monitor, virtual uart.
> 它同样用普通 ld.w / st.w 访问, 读延迟也是 1 拍, 因此 CPU 不必区分内存与外设. 注意它与 ex8 的 CSR 没有关系.

这里还有一个问题是, store 信号也是 EXE 阶段发出的, 这是由于, 流水线设计导致了, 如果 store 在 MEM 阶段发出, 那么很有可能和正在 EXE 阶段的 load 指令冲突.