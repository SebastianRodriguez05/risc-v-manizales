set root_dir [pwd]

create_project -name led -dir ./build -pn GW2A-LV18PG256C8/I7 -device_version C -force

add_file $root_dir/build/netlist_gw.v
add_file $root_dir/constraints/led.cst

set_option -top_module led
set_option -output_base_name led

run all
