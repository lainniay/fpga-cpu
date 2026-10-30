# ICache

Instructment-Cache, 用于缓存指令, 工作架构如下:

```mermaid
graph LR
  if(IF) --> ICache(ICache) --> Im(IMemory)
```

具体工作行为是:

1. IF 向 ICache 发送取值指令
2. ICache Miss, 从 IMem 里面读取数据
3. ICache 更新 Cache, 同时将指令内容返回给 IF

这里采用的具体架构是, IF 直接向 [inst_fect_mem](inst_fetch_mem.v)  模块发起取指请求, 其内部负责链接 [IMem](./inst_mem_adapter.v) 以及 [ICache](./icache.v).


## Protocol

主要是, IF 和 ICache, ICache 和 IMem 之间的沟通协议.

### IF & ICache

和 IF & ICache 相关的控制指令如下:

- `req_valid`
  - IF -> ICache, 用于表示 Request 本身有效
- `req_ready`
  - ICache -> IF, 用于表示 ICache 准备好接受 Request
- `rsp_valid`
  - ICache -> IF, 用于表示 Response 有效
- `rsp_ready`
  - IF -> ICache, 用于表示 IF 准备好接受 Response

最终, 组合出的条件如下:

- ICache 接受 Request:
  - `req_valid && req_ready`
- IF 消费 Response:
  - `rsp_valid && rsp_ready`
- Request 等待期间:
  - `req_valid=1 && req_ready=0`
  - `req_valid`, `req_pc` 保持不变, 等待 `req_ready`
- Response 等待期间:
  - `rsp_valid=1 && rsp_ready=0`
  - `rsp_valid`, `rsp_pc`, `rsp_inst` 不变, 等待 `rsp_ready`

这里主要的问题是, IF 向 ICache 发出 Request 之后, 就一直在等 Response. 但是需要注意的是, 由于 ID 并不一定允许指令进入, 同时在 [IF](./IF_stage.v) 里面, 对从 ICache 出来的指令不存在任何的锁存, 因此, 如果没有 `rep_ready` 告诉 ICache 当前能不能撤回数据, 就会导致数据丢失.

### ICache && IMem

和 ICache & IMem 相关的控制指令如下, input / output 相对于 ICache:

- `mem_req_valid`
  - ICache -> IMem, 用于表示 Request 本身有效
- `mem_req_ready`
  - IMem -> ICache, 用于表示 IMem 准备好接受 Request
- `mem_rsp_valid`
  - IMem -> ICache, 用于表示 Response 有效

其中, `mem_req_addr` 是 ICache 发送给 IMem 的 32 位读取地址, `mem_rsp_data` 是 IMem 返回给 ICache 的 32 位数据.

最终, 组合出的条件如下, 都在时钟沿判断:

- IMem 接受 Request:
  - `mem_req_valid && mem_req_ready`
- ICache 消费 Response:
  - `mem_rsp_valid`
- Request 等待期间:
  - `mem_req_valid=1 && mem_req_ready=0`
  - `mem_req_valid`, `mem_req_addr` 保持不变, 等待 `mem_req_ready`
- Response 返回时:
  - `mem_rsp_valid=1`
  - ICache 必须接收并保存 `mem_rsp_data`, 每个被接受的 Request 只返回一次

这里和 IF & ICache 的区别是, 不存在 `mem_rsp_ready`. ICache 发出 Request 之前, 已经预留了保存返回数据的位置, 数据返回之后可以直接写入缓存, 不需要等待 ID. 因此, IMem 不需要等待 ICache 允许消费 Response, ICache 也不能要求 IMem 保持 Response.


## ICache Structure

简单情况下, ICache 存放的是:

```
addr(32) -> inst(32)
```

但是, 如果需要从 ICache 里面拿指令, 就需要比较非常多的比较线路, 因此对 ICache 作出如下的改造.

具体而言, ICache 的结构如下:

```
valid [1] tag[22] word0[32] word1[32] word2[32] word3[32]
```

对应的 PC[32] 的结构, 注意这里的划分是 ICache 对于 PC 的划分, 而不是 PC 本身的划分:

```
tag[22] index[6] offset[2] byte[2]
```

这里需要注意的是, 由于 PC 是 4bit 对齐的, 因此 PC 的第二位一定是 `0x00`, 这在 [IF](./IF_stage.v) 中进行检查. 因此 ICache 从一开始就没必要存储后面的两个 Bit.

ICache 一次性读入 4 个 Word, 也就是 Cache Line, IMem 会被 Cache Line 划分出来, 当 Miss 的时候, 会读入 Miss 的 PC 所在的 Cache Line.

PC 中的 Index 用于判断, 这个指令应该装到哪一个 ICache 行中, 因为 ICache 一共有 64 行, 所以需要 6 个 bit 进行区分.

剩余的用作 Tag, 用于比较, 这里放的是不是对应的块.