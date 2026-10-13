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

# Ex4

加上新的运算指令: slti, sltui, andi, ori, xori, sll.w, srl.w, sra.w, pcaddu12i

| 指令 | 大致含义 | 核心操作 |
|---|---|---|
| `slti` | 有符号“小于立即数”比较 | `signed(rj) < signed(imm)` |
| `sltui` | 无符号“小于立即数”比较 | `unsigned(rj) < unsigned(signext(imm))` |
| `andi` | 按位与立即数 | `rj & imm` |
| `ori` | 按位或立即数 | `rj \| imm` |
| `xori` | 按位异或立即数 | `rj ^ imm` |
| `sll.w` | 32 位逻辑左移 | `rj[31:0] << rk[4:0]` |
| `srl.w` | 32 位逻辑右移 | `rj[31:0] >> rk[4:0]`，补 0 |
| `sra.w` | 32 位算术右移 | 按有符号 32 位右移 |
| `pcaddu12i` | `PC + (imm << 12)` | PC 相对地址生成 |


```c
slti:
    rd = ((signed)rj < sign_extend(si12)) ? 1 : 0;

sltui:
    rd = ((unsigned)rj <
          (unsigned)sign_extend(si12)) ? 1 : 0;

andi:
    rd = rj & zero_extend(ui12);

ori:
    rd = rj | zero_extend(ui12);

xori:
    rd = rj ^ zero_extend(ui12);


sll.w:
    rd = sign_extend_32(
        (uint32_t)rj << (rk & 31)
    );

srl.w:
    rd = sign_extend_32(
        (uint32_t)rj >> (rk & 31)
    );

sra.w:
    rd = sign_extend_32(
        (int32_t)rj >> (rk & 31)
    );

pcaddu12i:
    rd = PC + sign_extend(si20 << 12);
```

# Ex5

增加跳转指令: blt、bge、bltu、bgeu:

| 指令 | 含义 | 比较方式 |
|---|---|---|
| `blt` | Branch if Less Than | 有符号 `<` |
| `bge` | Branch if Greater or Equal | 有符号 `>=` |
| `bltu` | Branch if Less Than Unsigned | 无符号 `<` |
| `bgeu` | Branch if Greater or Equal Unsigned | 无符号 `>=` |

# Ex6

增加 load/store 指令: ld.b, ld.h, ld.bu, ld.hu, st.b, st.h.

| 指令 | 含义 | 宽度 | 扩展 |
|---|---|---|---|
| `ld.b` | 取字节, 符号扩展后写 rd | 1 字节 | SignExtend |
| `ld.h` | 取半字, 符号扩展后写 rd | 2 字节 | SignExtend |
| `ld.bu` | 取字节, 零扩展后写 rd | 1 字节 | ZeroExtend |
| `ld.hu` | 取半字, 零扩展后写 rd | 2 字节 | ZeroExtend |
| `st.b` | 把 rd[7:0] 写入内存 | 1 字节 | 不涉及 |
| `st.h` | 把 rd[15:0] 写入内存 | 2 字节 | 不涉及 |

在 vivado build 的时候发现.

虽然真实的数据在 MEM 阶段结束就已经拿到了, 但是如果直接在 MEM 阶段进行回传, 会导致 50MHz 的下一个时钟沿到来之前, 没法完全 MEM -> ID 写回的全部步骤.

因此, 对于 load 类指令需要拖到 WB 阶段再进行写回, 让 ID 的指令 Stall.

# Ex7

加上乘除法指令: mul.w, mulh.w, mulh.wu, div.w, mod.w, div.wu, mod.wu

| 指令 | 大致含义 | 核心操作 |
|---|---|---|
| `mul.w` | 乘法, 取乘积低 32 位 | `(rj * rk)[31:0]` |
| `mulh.w` | 有符号乘法, 取乘积高 32 位 | `(signed(rj) * signed(rk))[63:32]` |
| `mulh.wu` | 无符号乘法, 取乘积高 32 位 | `(unsigned(rj) * unsigned(rk))[63:32]` |
| `div.w` | 有符号除法, 取商 | `signed(rj) / signed(rk)` |
| `mod.w` | 有符号除法, 取余数 | `signed(rj) % signed(rk)` |
| `div.wu` | 无符号除法, 取商 | `unsigned(rj) / unsigned(rk)` |
| `mod.wu` | 无符号除法, 取余数 | `unsigned(rj) % unsigned(rk)` |

> 需要注意的是, 同一组 operand, 其经过有符号乘法, 和无符号乘法得到的结果是 mod 2^{32} 同余的.

需要注意的是, 除法是多周期的, 因此 es_ready_go 并不总是 1, 需要根据除法来进行判别. 而且, 除法的 done 只会在除法开始和除法结束的时候进行修改, 因此需要另一个 start 信号控制.

经过测试, mul 直接在 exe 阶段回传会导致超时, 因此延迟到 mem 阶段进行回传.

```c
mul.w:
    product = signed(rj) * signed(rk);
    rd = product[31:0];         // 低 32 位与无符号乘法结果相同

mulh.w:
    product = signed(rj) * signed(rk);
    rd = product[63:32];

mulh.wu:
    product = unsigned(rj) * unsigned(rk);
    rd = product[63:32];

div.w:
    rd = signed(rj) / signed(rk);

mod.w:
    rd = signed(rj) % signed(rk);

div.wu:
    rd = unsigned(rj) / unsigned(rk);

mod.wu:
    rd = unsigned(rj) % unsigned(rk);
```
