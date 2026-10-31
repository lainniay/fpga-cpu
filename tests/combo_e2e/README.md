# Combined Extension End-to-End Tests

These tests run LoongArch firmware that simultaneously exercises:

- branch prediction and redirects,
- ICache fetch hits and misses,
- UART RX/TX and MMIO.

## Run

```sh
make combo-e2e
```

or all extension tests:

```sh
make ext-e2e
```

## Tests

| ID | Test | Combined behavior |
|---:|---|---|
| 1 | `uart_echo_until_ff` | Receive, branch, echo bytes until `0xFF` |
| 2 | `uart_command_dispatch` | Dispatch commands to different branch targets and replies |
| 3 | `uart_checksum4` | Receive four bytes in a loop, sum, send checksum |
| 4 | `uart_counted_echo` | First byte is the count; echo that many bytes |
| 5 | `uart_parity_echo` | Branch on received-byte parity and send 0/1 |

The testbench drives `uart_rx`, decodes `uart_tx`, and checks predictor and
ICache activity through integrated SoC signals. Firmware reports completion
through the virtual UART register.

## Requirements

- Icarus Verilog
- `llvm-mc` and `llvm-objcopy` with LoongArch32 support
- Python 3

Set `LLVM_BIN` if LLVM is not in `PATH`.
