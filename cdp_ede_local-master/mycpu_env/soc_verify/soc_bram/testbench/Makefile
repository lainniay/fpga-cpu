.PHONY: clean
IVERILOG_DIR = project/loongson.sim/sim_1/behav/iverilog
MYCPU_SRCS   = ../../../myCPU/*.v
RTL_SRCS     = ../rtl/*.v ../rtl/*/*.v
TB_SRCS      = sync_ram.v mycpu_tb.v

iverilog : $(IVERILOG_DIR)/gettrace
	cd $(IVERILOG_DIR) && vvp ./gettrace

$(IVERILOG_DIR)/gettrace: $(MYCPU_SRCS) $(RTL_SRCS) $(TB_SRCS)
	mkdir -p $(IVERILOG_DIR) && iverilog -Wall -I../../../myCPU/ -o $(IVERILOG_DIR)/gettrace $(MYCPU_SRCS) $(RTL_SRCS) $(TB_SRCS)

clean : 
	rm -rf ./project 
