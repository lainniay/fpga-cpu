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

build=build/ext_e2e
mkdir -p "$build"

if ! iverilog -g2012 -Wall -I cdp_ede_local-master/mycpu_env/myCPU \
    -s ext_e2e_tb -o "$build/sim.vvp" \
    tests/ext_e2e/ext_e2e_tb.sv \
    tests/ext_e2e/sync_ram_e2e.v \
    cdp_ede_local-master/mycpu_env/myCPU/*.v \
    cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/rtl/*.v \
    cdp_ede_local-master/mycpu_env/soc_verify/soc_bram/rtl/*/*.v \
    >"$build/compile.log" 2>&1; then
    cat "$build/compile.log" >&2
    exit 1
fi

for test_id in $(seq 1 6); do
    src=$(find tests/ext_e2e -maxdepth 1 -name "$(printf '%02d' "$test_id")_*.S" -print -quit)
    if [[ -z "$src" ]]; then
        echo "missing test source for $test_id" >&2
        exit 1
    fi

    obj="$build/test${test_id}.o"
    bin="$build/test${test_id}.bin"
    mif="$build/inst_ram.mif"
    log="$build/test${test_id}.log"

    "$llvm_bin/llvm-mc" -triple=loongarch32 -I tests/ext_e2e \
        -filetype=obj "$src" -o "$obj"
    "$llvm_bin/llvm-objcopy" -O binary -j .text "$obj" "$bin"
    python3 tests/ext_e2e/bin2mif.py "$bin" "$mif"

    if ! vvp "$build/sim.vvp" +TEST="$test_id" \
        +INST_MIF="$mif" >"$log" 2>&1; then
        cat "$log" >&2
        echo "FAIL: test $test_id" >&2
        exit 1
    fi
    if ! grep -q "PASS: ext_e2e test${test_id} " "$log"; then
        cat "$log" >&2
        echo "FAIL: test $test_id did not report PASS" >&2
        exit 1
    fi
    grep "PASS: ext_e2e" "$log"
done

echo "PASS: all 6 branch-predictor and ICache end-to-end tests"
