GW_SH       ?= /home/pci/Descargas/IDE/bin/gw_sh
TOP         := led
SRC         := src/led_blink.v
CST         := constraints/led.cst
NETLIST     := build/netlist_gw.v
BITSTREAM   := build/led/impl/pnr/led.fs

export QT_QPA_PLATFORM := offscreen

.PHONY: all synth pnr program clean

all: pnr

$(NETLIST): $(SRC)
	mkdir -p build
	yosys synth.ys

synth: $(NETLIST)

$(BITSTREAM): $(NETLIST) $(CST)
	$(GW_SH) pnr.tcl

pnr: $(BITSTREAM)

program: $(BITSTREAM)
	openFPGALoader -b tangprimer20k $(BITSTREAM)

clean:
	rm -rf build
