# Phase 1 — GHDL + Yosys + nextpnr + icestorm flow.
#
#   make sim          run the self-checking testbench (do this FIRST, always)
#   make wave         sim + open the waveform in GTKWave
#   make synth        VHDL -> netlist (yosys via ghdl-yosys-plugin)
#   make bit          netlist -> place/route -> bitstream
#   make time         static timing estimate (icetime)
#   make prog         flash the board (iceprog)
#   make clean
#
#   make BOARD=hx8k bit    for the iCE40-HX8K-B-EVN (default: icestick)

BOARD ?= icestick
TOP    = top
TB     = nco_tb

RTL    = rtl/nco.vhd rtl/top.vhd
TB_SRC = tb/nco_tb.vhd

ifeq ($(BOARD),icestick)
  DEVICE  = hx1k
  PACKAGE = tq144
  PCF     = constraints/icestick.pcf
else ifeq ($(BOARD),hx8k)
  DEVICE  = hx8k
  PACKAGE = ct256
  PCF     = constraints/hx8k.pcf
else
  $(error unknown BOARD '$(BOARD)': use icestick or hx8k)
endif

GHDL_FLAGS = --std=08 --workdir=build

# OSS CAD Suite's libgrt.a targets glibc >= 2.38; this host (Ubuntu 22.04) has
# 2.35, so elaboration needs the __isoc23_* forwarding shim. Built from
# ~/tools/glibc-isoc23-shim.c — drop this once the distro glibc is >= 2.38.
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim wave synth bit time prog clean

# ---------- simulation (GHDL) ----------

sim: | build
	ghdl -a $(GHDL_FLAGS) $(RTL) $(TB_SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) $(TB)
	ghdl -r $(GHDL_FLAGS) $(TB) --wave=build/$(TB).ghw --assert-level=failure

wave: sim
	gtkwave build/$(TB).ghw &

# ---------- synthesis -> bitstream ----------

synth: build/$(TOP).json
bit:   build/$(TOP).bin

build/$(TOP).json: $(RTL) | build
	yosys -m ghdl -p 'ghdl $(GHDL_FLAGS) $(RTL) -e $(TOP); synth_ice40 -top $(TOP) -json $@'

build/$(TOP).asc: build/$(TOP).json $(PCF)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --pcf $(PCF) \
	              --json $< --asc $@ --freq 12

build/$(TOP).bin: build/$(TOP).asc
	icepack $< $@

time: build/$(TOP).asc
	icetime -d $(DEVICE) -p $(PCF) -t $<

prog: build/$(TOP).bin
	iceprog $<

build:
	mkdir -p build

clean:
	rm -rf build
