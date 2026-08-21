# Lesson 08 solution — minimal GHDL sim flow. Usage: make sim  (after
# sourcing ~/tools/oss-cad-suite/environment). Mirrors fpga/phase1/Makefile
# in miniature — same flags, same shim, no synthesis targets.

TB         = dsm_dac_tb
GHDL_FLAGS = --std=08 --workdir=build
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim clean

sim: | build
	ghdl -a $(GHDL_FLAGS) dsm_dac.vhd dsm_dac_tb.vhd
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --assert-level=failure

build:
	mkdir -p build

clean:
	rm -rf build
