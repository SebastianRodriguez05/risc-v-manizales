set root_dir [pwd]

create_project -name spi_flash_emu -dir ./build -pn GW2A-LV18PG256C8/I7 -device_version C -force

add_file $root_dir/build/netlist_gw.v
add_file $root_dir/constraints/tang_primer_20k.cst

set_option -top_module top
set_option -output_base_name spi_flash_emu

run all
