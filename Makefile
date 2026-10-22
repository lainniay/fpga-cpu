SHELL := /bin/sh

PROJECT_DIR := cdp_ede_local-master
MYCPU_ENV := $(PROJECT_DIR)/mycpu_env
CPU_DIR := $(MYCPU_ENV)/myCPU
GETTRACE_DIR := $(MYCPU_ENV)/gettrace
SIM_DIR := $(MYCPU_ENV)/soc_verify/soc_bram/testbench
WAVEFORM := $(SIM_DIR)/project/loongson.sim/sim_1/behav/iverilog/dump.vcd
TEST ?= ex1

INST_MIF := $(MYCPU_ENV)/func/obj/inst_ram.mif
DATA_MIF := $(MYCPU_ENV)/func/obj/data_ram.mif
GOLDEN   := $(GETTRACE_DIR)/golden_trace.txt
# wildcard: mif 不存在时不要变成无法构建的依赖, 否则 make 会报 'No rule to make target'
MIFS := $(wildcard $(INST_MIF) $(DATA_MIF))

.PHONY: help tools select-test golden sim run lint synth-check check fmt fmt-check clean

RTL_FILES := $(wildcard $(CPU_DIR)/*.v)
VERIBLE_FORMAT := verible-verilog-format --flagfile=.verible-format

help:
	@printf '%s\n' \
	  'make run TEST=ex1    Select ex1, generate golden trace, and simulate CPU' \
	  'make sim             Simulate (regenerates golden trace if the mif changed)' \
	  'make check           Run Verilator lint and Yosys synthesis checks' \
	  'make test-ex9-1       Run directed synchronous exception tests' \
	  'make test-ex9-1-official Run the isolated official ex9_1 functions' \
	  'make fmt             Format myCPU RTL in place with Verible' \
	  'make fmt-check       Report RTL files that are not formatted' \
	  'make clean           Remove generated simulation files and traces'

tools:
	@command -v iverilog
	@command -v vvp
	@command -v verilator
	@command -v yosys
	@printf 'HDL toolchain is available.\n'

select-test:
	@./scripts/select-test.sh "$(TEST)"

# golden_trace 由 mif 决定: mif 变了(或 trace 缺失)就必须重建, 否则对比基准会错位
GOLDEN_GUARD = test -f "$(INST_MIF)" || { printf 'No test selected; run make select-test TEST=ex1 first.\n' >&2; exit 1; }

$(GOLDEN): $(MIFS)
	@$(GOLDEN_GUARD)
	@$(MAKE) -C "$(GETTRACE_DIR)" iverilog

golden:
	@$(GOLDEN_GUARD)
	@rm -f "$(GOLDEN)"
	@$(MAKE) --no-print-directory $(GOLDEN)

sim: $(GOLDEN)
	@$(GOLDEN_GUARD)
	@$(MAKE) -C "$(SIM_DIR)" iverilog
	@printf 'Waveform: %s\n' "$(WAVEFORM)"

# 单条顺序 recipe: 避免 make -j 下 select-test 与 golden 并发导致 golden 读到半拷贝的 mif
run:
	@./scripts/select-test.sh "$(TEST)"
	@$(MAKE) --no-print-directory golden
	@$(MAKE) --no-print-directory sim

fmt:
	@$(VERIBLE_FORMAT) --inplace $(RTL_FILES)
	@printf 'Formatted %s file(s).\n' "$$(printf '%s\n' $(RTL_FILES) | wc -l | tr -d ' ')"

fmt-check:
	@status=0; \
	for f in $(RTL_FILES); do \
	  $(VERIBLE_FORMAT) --verify "$$f" || status=1; \
	done; \
	if [ $$status -eq 0 ]; then printf 'RTL formatting is clean.\n'; \
	else printf 'Formatting diffs found; run make fmt.\n' >&2; exit 1; fi

lint:
	@verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-MULTITOP -Wno-UNUSEDSIGNAL --top-module mycpu_top -I"$(CPU_DIR)" "$(CPU_DIR)"/*.v

synth-check:
	@yosys -q -p 'read_verilog $(CPU_DIR)/*.v; hierarchy -check -top mycpu_top; proc; check'

check: lint synth-check

# NOTE: ex9 独立同步异常测试, 不依赖 ex9_2 的计数器和中断.
.PHONY: test-ex9-1
test-ex9-1:
	@mkdir -p build/ex9_1
	@iverilog -g2012 -Wall -s ex9_1_tb -I"$(CPU_DIR)" -o build/ex9_1/directed $(RTL_FILES) tests/ex9_1_tb.v
	@vvp build/ex9_1/directed
	@iverilog -g2012 -Wall -s ex9_if_tb -I"$(CPU_DIR)" -o build/ex9_1/if-stage $(RTL_FILES) tests/ex9_if_tb.v
	@vvp build/ex9_1/if-stage

# NOTE: ex9 保留官方函数体的独立调度测试, 不等于完整 Ex9 回归.
.PHONY: test-ex9-1-official
test-ex9-1-official:
	@mkdir -p build/ex9_1
	@iverilog -g2012 -Wall -s ex9_1_official_tb -I"$(CPU_DIR)" -o build/ex9_1/official $(RTL_FILES) $(MYCPU_ENV)/soc_verify/soc_bram/rtl/*.v $(MYCPU_ENV)/soc_verify/soc_bram/rtl/*/*.v tests/ex9_1_official_tb.v
	@vvp build/ex9_1/official

clean:
	@rm -rf "$(GETTRACE_DIR)/gettrace.sim"
	@rm -f "$(GETTRACE_DIR)/golden_trace.txt"
	@rm -rf "$(SIM_DIR)/project"
	@printf 'Generated simulation files removed.\n'
