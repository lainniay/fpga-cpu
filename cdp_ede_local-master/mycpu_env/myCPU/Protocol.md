# Protocol

在五级流水线的相邻两级, 比如说 `X -> Y` 采用: 

```
X --X_to_Y_valid-> Y
X <--Y_allowin---- Y
```

作为沟通的 Protocol. 只有 `X_to_Y_valid && Y_allowin == 1` 的情况下, 才能在下一个时钟沿进行更新.

对于每一级 `X`, 其都可以使用下面的模板来规划是否进行更新:

```verilog
// 当前 Stage 上的指令的工作, 在当前的时钟沿有没有完成
assign stage_ready_go = ...;

// 当前 Stage 允许进入
// stage_valid 表明当前 Stage 有没有 Inst, 比如说 bubble 的时候, stage_valid=0
assign stage_allowin =
    !stage_valid ||
    (stage_ready_go && next_stage_allowin);

// 当前 Stage 准备好进入下一个 Stage
assign stage_to_next_valid =
    stage_valid && stage_ready_go;
```

统一的更新模板:

```verilog
always @(posedge clk) begin
    if (reset)                       x_valid_r <= 1'b0;
    else if (x_allowin)              x_valid_r <= up_to_x_valid;    
    if (up_to_x_valid && x_allowin)  x_bus_r   <= up_to_x_bus;     
end
```

这里的 x_allowin, 就写 x_valid_r 是为了实现 bubble, 因为 bubble 不需要读取总线, 但是需要明确的占用一个周期, 从而需要让整个单元空着一个周期.

