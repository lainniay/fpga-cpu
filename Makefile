SHELL := /bin/sh

PROJECT_DIR := cdp_ede_local-master
MYCPU_ENV := $(PROJECT_DIR)/mycpu_env
CPU_DIR := $(MYCPU_ENV)/myCPU
GETTRACE_DIR := $(MYCPU_ENV)/gettrace
SIM_DIR := $(MYCPU_ENV)/soc_verify/soc_bram/testbench
WAVEFORM := $(SIM_DIR)/project/loongson.sim/sim_1/behav/iverilog/dump.vcd
TEST ?= ex1

.PHONY: help tools select-test golden sim run lint synth-check check fmt fmt-check clean

RTL_FILES := $(wildcard $(CPU_DIR)/*.v)
VERIBLE_FORMAT := verible-verilog-format --flagfile=.verible-format

help:
	@printf '%s\n' \
	  'make run TEST=ex1    Select ex1, generate golden trace, and simulate CPU' \
	  'make sim             Simulate with the currently selected test images' \
	  'make check           Run Verilator lint and Yosys synthesis checks' \
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

golden:
	@test -f "$(MYCPU_ENV)/func/obj/inst_ram.mif" || { printf 'No test selected; run make select-test TEST=ex1 first.\n' >&2; exit 1; }
	@$(MAKE) -C "$(GETTRACE_DIR)" iverilog

sim:
	@test -f "$(GETTRACE_DIR)/golden_trace.txt" || { printf 'Missing golden trace; run make golden first.\n' >&2; exit 1; }
	@$(MAKE) -C "$(SIM_DIR)" iverilog
	@printf 'Waveform: %s\n' "$(WAVEFORM)"

run: select-test golden sim

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

clean:
	@rm -rf "$(GETTRACE_DIR)/gettrace.sim"
	@rm -f "$(GETTRACE_DIR)/golden_trace.txt"
	@rm -rf "$(SIM_DIR)/project"
	@printf 'Generated simulation files removed.\n'
