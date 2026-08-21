# Lesson 10 solutions — freq_meas + osc_model. Usage: make sim
# (after sourcing ~/tools/oss-cad-suite/environment). Mirrors
# tutorial/Makefile — same flags, same shim. No synthesis targets:
# osc_model is simulation-only and freq_meas is synthesized as part of
# theremin_top in lesson14, not here.

TB         = freq_meas_tb
SRC        = osc_model.vhd freq_meas.vhd freq_meas_tb.vhd
GHDL_FLAGS = --std=08 --workdir=build
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim clean

sim: | build
	ghdl -a $(GHDL_FLAGS) $(SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --assert-level=failure

build:
	mkdir -p build

clean:
	rm -rf build
