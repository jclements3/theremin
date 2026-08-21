# Lesson 13 solutions — pitch_map. Usage: make sim
# (after sourcing ~/tools/oss-cad-suite/environment). Mirrors
# tutorial/Makefile — same flags, same shim. No synthesis targets:
# pitch_map is synthesized as part of theremin_top in lesson14, not here.

TB         = pitch_map_tb
SRC        = pitch_map.vhd pitch_map_tb.vhd
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
