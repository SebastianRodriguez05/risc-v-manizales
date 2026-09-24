# risc-v-manizales

Documentación de las pruebas realizadas alrededor del procesador **femto_UN**: desarrollo en FPGA, firmware, instrumentación y diseño de la placa tester para el ASIC fabricado con Tiny Tapeout.

Cada prueba tiene su propia carpeta con el código, los archivos necesarios para reproducirla y un `README.md` con objetivo, conexiones, pasos, resultados y problemas encontrados.

## Hardware usado

- **Sipeed Tang Primer 20K Dock** (FPGA GW2A-LV18PG256C8/I7)
- **Tiny Tapeout Demo Board v3.2** (RP2040) con el chip femto_UN
- **ESP32-C6-WROOM-1** (StudioPixels) como maestro SPI de pruebas
- **Analog Discovery 2** y **Nordic PPK2** para medición

## Estructura del repo

```
risc-v-manizales/
├── docs/        # documentación general (toolchain, pinouts, mediciones)
├── fpga/        # pruebas en la Tang Primer 20K
├── firmware/    # código para microcontroladores (ESP32, femtoRV32)
├── pcb/         # placa tester en KiCad
└── mult_32/     # multiplicador de 32 bits en Verilog
```

## Pruebas

| Prueba | Descripción | Estado |
|--------|-------------|--------|
| [led_blink](fpga/led_blink) | Flujo mínimo Yosys + Gowin en Tang Primer 20K 

**Estados:**  Funciona ·  En progreso ·  Falló

## Documentación

- [Toolchain y entorno de trabajo](docs/toolchain.md): instalación de todas las herramientas y problemas conocidos en Fedora 44.

## Cómo empezar

1. Montar el entorno siguiendo [`docs/toolchain.md`](docs/toolchain.md).
2. Probar el flujo con [`fpga/led_blink`](fpga/led_blink), que sirve como plantilla para los demás proyectos en FPGA.

## Convenciones

- **Una prueba = una carpeta con su `README.md`.** No se sube código sin documentación.
- Las capturas, fotos y GIFs van en una carpeta `img/` dentro de cada prueba.
- Los archivos generados (`build/`, logs, ondas `.vcd`) no se suben; ver `.gitignore`.
- Mensajes de commit con el nombre de la prueba como prefijo:
  `led_blink: ...`, `docs: ...`, `spi_flash_emu: ...`

## Referencias

- [cicamargoba/femto_UN](https://github.com/cicamargoba/femto_UN): repositorio de referencia del femto_UN
- [ArthurHeymans/tang_20k_spi_flash](https://github.com/ArthurHeymans/tang_20k_spi_flash): base del emulador de flash SPI

## Licencia

Ver [LICENSE](LICENSE).

1. `TOP`, `SRC`, `CST` y `BITSTREAM` en el `Makefile`
2. `read_verilog` y `-top` en `synth.ys`
3. `-name`, el `.cst`, `-top_module` y `-output_base_name` en `pnr.tcl`
