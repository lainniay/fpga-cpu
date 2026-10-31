#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_dir"
mkdir -p build/uart_mmio
rtl=cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/rtl/UART

printf '%s\n' '[RUN] UART TX standalone'
iverilog -g2012 -Wall -s uart_tx_tb \
    -o build/uart_mmio/uart_tx_tb.vvp \
    tests/uart_mmio/uart_tx_tb.sv "$rtl/uart_tx.v"
vvp build/uart_mmio/uart_tx_tb.vvp | tee build/uart_mmio/tx.log

printf '%s\n' '[RUN] UART RX regression'
iverilog -g2012 -Wall -s uart_rx_tb \
    -o build/uart_mmio/uart_rx_tb.vvp \
    tests/uart_rx/uart_rx_tb.sv "$rtl/uart_rx.v"
vvp build/uart_mmio/uart_rx_tb.vvp | tee build/uart_mmio/rx.log

printf '%s\n' '[RUN] UART MMIO with real RX and TX'
iverilog -g2012 -Wall -s uart_mmio_tb \
    -o build/uart_mmio/uart_mmio_tb.vvp \
    tests/uart_mmio/uart_mmio_tb.sv \
    "$rtl/uart_mmio.v" "$rtl/uart_rx.v" "$rtl/uart_tx.v"
vvp build/uart_mmio/uart_mmio_tb.vvp | tee build/uart_mmio/mmio.log
