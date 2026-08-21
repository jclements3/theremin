# Lesson 14 — theremin_top integration. Usage (after sourcing
# ~/tools/oss-cad-suite/environment):
#
#   make sim              end-to-end testbench (osc_model hand sweep)
#   make synth            VHDL -> netlist (yosys via ghdl-yosys-plugin)
#   make bit              netlist -> place/route -> bitstream
#   make time             static timing estimate (icetime)
#   make prog             flash the board (iceprog; lesson99)
#   make clean
#
#   make BOARD=hx8k bit   for the iCE40-HX8K-B-EVN (default: icestick)
#
# Mirrors fpga/phase1/Makefile. osc_model.vhd is SIMULATION-ONLY and must
# never appear in RTL (yosys would reject it).

BOARD ?= icestick
TOP    = theremin_top
TB    ?= theremin_top_tb

RTL     = sync_2ff.vhd freq_meas.vhd pitch_map.vhd nco.vhd sine_lut.vhd \
          dsm_dac.vhd theremin_top.vhd
SIM_SRC = osc_model.vhd theremin_top_tb.vhd

ifeq ($(BOARD),icestick)
  DEVICE  = hx1k
  PACKAGE = tq144
  PCF     = icestick.pcf
else ifeq ($(BOARD),hx8k)
  DEVICE  = hx8k
  PACKAGE = ct256
  PCF     = hx8k.pcf
else
  $(error unknown BOARD '$(BOARD)': use icestick or hx8k)
endif

GHDL_FLAGS = --std=08 --workdir=build

# OSS CAD Suite's libgrt.a targets glibc >= 2.38; on older hosts elaboration
# needs the __isoc23_* forwarding shim (see fpga/phase1/Makefile).
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim synth bit time prog clean

# ---------- simulation (GHDL) ----------

sim: | build
	ghdl -a $(GHDL_FLAGS) $(RTL) $(SIM_SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --assert-level=failure

# ---------- synthesis -> bitstream ----------

synth: build/$(TOP).json
bit:   build/$(TOP)-$(BOARD).bin

build/$(TOP).json: $(RTL) | build
	yosys -m ghdl -p 'ghdl $(GHDL_FLAGS) $(RTL) -e $(TOP); synth_ice40 -top $(TOP) -json $@'

build/$(TOP)-$(BOARD).asc: build/$(TOP).json $(PCF)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --pcf $(PCF) \
	              --json $< --asc $@ --freq 12

build/$(TOP)-$(BOARD).bin: build/$(TOP)-$(BOARD).asc
	icepack $< $@

time: build/$(TOP)-$(BOARD).asc
	icetime -d $(DEVICE) -p $(PCF) -t $<

prog: build/$(TOP)-$(BOARD).bin
	iceprog $<

build:
	mkdir -p build

clean:
	rm -rf build
