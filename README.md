# ris-v-manizales
Pruebas y documentación del ecosistema femto_UN: emulador de flash SPI en Tang Primer 20K, placa tester en KiCad, mult_32 y flujo Yosys + Gowin

## Pruebas

| Carpeta | Prueba |
|---------|--------|
| [`fpga/led_blink`](fpga/led_blink) | Flujo Yosys + Gowin en la Tang Primer 20K |
| [`fpga/spi_flash_emu`](fpga/spi_flash_emu) | Emulador de flash SPI en la FPGA, probado con el ESP32-C6 |
| [`docs/mediciones/consumo_ppk2`](docs/mediciones/consumo_ppk2) | Capacidad de corriente del 3V3 de la demo board |
| [`asic/hello_world_uart`](asic/hello_world_uart) | Primer arranque del femto_UN: Hello World por UART |
| [`asic/ram_test`](asic/ram_test) | RAM SPI (FM25V02) con el femto_UN: lectura, escritura y mayúsculas |
