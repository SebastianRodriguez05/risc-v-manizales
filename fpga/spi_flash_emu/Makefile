GW_SH       ?= /home/pci/Descargas/IDE/bin/gw_sh
TOP         := top
SRC         := rtl/spi_slave_flash.v rtl/top.v
CST         := constraints/tang_primer_20k.cst
NETLIST     := build/netlist_gw.v
BITSTREAM   := build/spi_flash_emu/impl/pnr/spi_flash_emu.fs

export QT_QPA_PLATFORM := offscreen

.PHONY: all synth pnr program sim wave clean

all: pnr

$(NETLIST): rtl/spi_slave_flash.v rtl/top.v
	mkdir -p build
	yosys synth.ys

synth: $(NETLIST)

$(BITSTREAM): $(NETLIST) $(CST)
	$(GW_SH) pnr.tcl

pnr: $(BITSTREAM)

program: $(BITSTREAM)
	openFPGALoader -b tangprimer20k $(BITSTREAM)

sim:
	iverilog -o sim/tb.out rtl/spi_slave_flash.v sim/tb_spi_slave_flash.v
	cd sim && vvp tb.out

wave: sim
	gtkwave sim/tb_spi_slave_flash.vcd &

clean:
	rm -rf build sim/tb.out sim/*.vcd
