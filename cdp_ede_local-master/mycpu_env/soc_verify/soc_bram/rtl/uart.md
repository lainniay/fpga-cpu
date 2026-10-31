# Address Space

[SOC](./soc_lite_top.v) 通过地址范围来区分是 DRam, 还是 Confreg, 通过 bridge1x2 模块将不同的地址分开.

# Uart 

在 [Uart](./UART/uart_mmio.v) 接入到 [SOC](./soc_lite_top.v) 的时候, 为了实现简单, 并没有修改 [Bridge](./BRIDGE/bridge_1x2.v), 而是直接和 [Bridge](./BRIDGE/bridge_1x2.v) 并列, 在 [SOC](./soc_lite_top.v) 根据地址范围进行划分.




