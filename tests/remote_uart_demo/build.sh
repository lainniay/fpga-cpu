#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"

llvm_bin=${LLVM_BIN:-}
if [[ -z "$llvm_bin" ]]; then
    if command -v llvm-mc >/dev/null 2>&1 && command -v llvm-objcopy >/dev/null 2>&1; then
        llvm_bin=$(dirname "$(command -v llvm-mc)")
    elif [[ -x /opt/homebrew/opt/llvm/bin/llvm-mc ]]; then
        llvm_bin=/opt/homebrew/opt/llvm/bin
    else
        echo "llvm-mc/llvm-objcopy not found; set LLVM_BIN" >&2
        exit 1
    fi
fi

build=build/remote_uart_demo
mkdir -p "$build" cdp_ede_local-master/mycpu_env/func/obj

"$llvm_bin/llvm-mc" -triple=loongarch32 -I tests/remote_uart_demo \
    -filetype=obj tests/remote_uart_demo/uart_banner.S -o "$build/uart_banner.o"
"$llvm_bin/llvm-objcopy" -O binary -j .text "$build/uart_banner.o" "$build/uart_banner.bin"
python3 tests/remote_uart_demo/bin2coe.py "$build/uart_banner.bin" \
    cdp_ede_local-master/mycpu_env/func/obj/inst_ram.mif \
    cdp_ede_local-master/mycpu_env/func/obj/inst_ram.coe

if ! iverilog -g2012 -Wall -I cdp_ede_local-master/mycpu_env/myCPU \
    -s uart_banner_tb -o "$build/sim.vvp" \
    tests/remote_uart_demo/uart_banner_tb.sv \
    tests/remote_uart_demo/sync_ram_demo.v \
    cdp_ede_local-master/mycpu_env/myCPU/*.v \
    cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/rtl/*.v \
    cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/rtl/*/*.v \
    >"$build/compile.log" 2>&1; then
    cat "$build/compile.log" >&2
    exit 1
fi

vvp "$build/sim.vvp"

if ! iverilog -g2012 -Wall -I cdp_ede_local-master/mycpu_env/myCPU \
    -s remote_top_tb -o "$build/remote_top.vvp" \
    tests/remote_uart_demo/remote_top_tb.sv \
    tests/remote_uart_demo/sync_ram_demo.v \
    cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/run_vivado/remote/remote2local.v \
    cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/run_vivado/remote/loongson_remote_top.v \
    cdp_ede_local-master/mycpu_env/myCPU/*.v \
    cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/rtl/*.v \
    cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/rtl/*/*.v \
    >"$build/remote_compile.log" 2>&1; then
    cat "$build/remote_compile.log" >&2
    exit 1
fi

vvp "$build/remote_top.vvp"
