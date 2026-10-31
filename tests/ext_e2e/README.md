# CPU Extension End-to-End Tests

These tests run LoongArch firmware on the full SoC and exercise the branch
predictor and instruction cache through real instruction fetch and branch
execution.

## Run

```sh
make bp-icache-e2e
```

or run all extension tests, including UART:

```sh
make ext-e2e
```

## Requirements

- Icarus Verilog
- `llvm-mc` and `llvm-objcopy` with LoongArch32 support
- Python 3

Set `LLVM_BIN` if the LLVM tools are not in `PATH`.

## Tests

| ID | Test | Focus |
|---:|---|---|
| 1 | `bp_loop` | Repeated taken loop branch trains the predictor |
| 2 | `bp_alternating` | Alternating branch outcomes and nested control flow |
| 3 | `bp_back_to_back` | Repeated multiple branches in one loop |
| 4 | `icache_sequential` | Sequential execution across several cache lines |
| 5 | `icache_loop` | Repeated execution of a loop line |
| 6 | `icache_branch` | Branch to a non-sequential cache line |

The testbench observes the integrated `mispredict`, predictor query and ICache
`query_hit` signals. Branch tests require at least one predictor hit, taken
prediction and mispredict. ICache tests require at least one cache hit and one
miss. Firmware reports success or failure through the virtual UART register.
