# UART CPU End-to-End Tests

These tests run actual LoongArch instructions on the SoC and exercise the complete path:

```text
CPU fetch/execute -> data bus -> UART MMIO -> UART TX/RX -> CPU checks
```

They use a 50 MHz `cpu_clk` model and 115200 8N1, matching the integrated SoC.

## Requirements

- Icarus Verilog
- `llvm-mc` and `llvm-objcopy` with LoongArch32 support
- Python 3

If LLVM tools are not in `PATH`, set:

```sh
LLVM_BIN=/path/to/llvm/bin make uart-e2e
```

## Run

```sh
make uart-e2e
```

or:

```sh
bash tests/uart_e2e/run.sh
```

Generated programs, MIF files and simulation logs are written under:

```text
build/uart_e2e/
```

## Tests

| ID | Test | Checks |
|---:|---|---|
| 1 | `tx_single` | Send one byte and wait for TX ready |
| 2 | `tx_pattern` | Send 00, FF, AA, 55 with ready polling |
| 3 | `tx_low_byte` | TXDATA write uses only the low byte |
| 4 | `status_initial` | Reset STATUS has TX_READY=1 and RX_VALID=0 |
| 5 | `rx_single` | Receive one byte and compare RXDATA |
| 6 | `rx_read_clear` | Reading RXDATA clears RX_VALID |
| 7 | `rx_two_bytes` | Receive two separated bytes |
| 8 | `full_duplex` | Simultaneous TX and RX |
| 9 | `rx_false_start` | Recover from a false start and receive a valid byte |
| 10 | `tx_busy` | A second TXDATA write while busy is ignored |

The testbench drives `uart_rx`, decodes `uart_tx`, and watches the virtual UART
register used by the firmware to report success or failure.
