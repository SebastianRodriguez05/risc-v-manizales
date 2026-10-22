# RISC-V-Manizales

Pruebas y documentación del ecosistema **femto_UN**: emulador de flash SPI en Tang Primer 20K, placa tester en KiCad y flujo Yosys + Gowin.

Universidad Nacional de Colombia, sede Manizales.

---

## Tabla de contenido

1. [Descripción general](#descripción-general)
2. [Contexto: el procesador femto_UN](#contexto-el-procesador-femto_un)
3. [Pruebas](#pruebas)
4. [Estructura del repositorio](#estructura-del-repositorio)
5. [Hardware utilizado](#hardware-utilizado)
6. [Herramientas de software](#herramientas-de-software)
7. [Descripción detallada de las pruebas](#descripción-detallada-de-las-pruebas)
8. [Placa tester femto_UN_tester](#placa-tester-femto_un_tester)
9. [Configuración del entorno](#configuración-del-entorno)
10. [Problemas encontrados y soluciones](#problemas-encontrados-y-soluciones)
11. [Estado actual y trabajo futuro](#estado-actual-y-trabajo-futuro)
12. [Referencias](#referencias)

---

## Descripción general

Este repositorio reúne el trabajo experimental realizado alrededor del procesador **femto_UN**, un núcleo RISC-V de 32 bits basado en FemtoRV32 y fabricado como circuito integrado a través del programa Tiny Tapeout. El objetivo es documentar, de forma reproducible, cada una de las pruebas de puesta en marcha (bring-up), verificación y caracterización del chip, así como las herramientas y el hardware auxiliar desarrollados para ello.

El trabajo se organiza en cuatro líneas principales:

- **Flujo de FPGA automatizado** con Yosys y Gowin EDA para la tarjeta Sipeed Tang Primer 20K, con el fin de, en el futuro, emular memorias y otros procesadores (por ejemplo, una segunda versión del femto_UN) en lógica programable.
- **Emulación de memoria flash SPI**, tanto en FPGA como en un microcontrolador ESP32-C6, para suplir la memoria de programa del femto_UN.
- **Pruebas sobre el chip real** montado en la Tiny Tapeout Demo Board: arranque, comunicación UART y uso de memoria RAM SPI externa.
- **Diseño de una placa tester** en KiCad para caracterizar el chip con instrumentación externa.

Cada prueba cuenta con su propia carpeta y su propio README, donde se describen el montaje, el procedimiento, los resultados y las evidencias (capturas de analizador lógico, mediciones y código fuente).

---

## Contexto: el procesador femto_UN

El femto_UN es un procesador RISC-V (RV32) de arquitectura mínima, diseñado en el marco de los cursos de diseño digital y VLSI de la Universidad Nacional de Colombia y fabricado mediante Tiny Tapeout sobre el PDK abierto SkyWater sky130.

Características relevantes para las pruebas de este repositorio:

| Aspecto | Descripción |
|---------|-------------|
| Núcleo | FemtoRV32 (RISC-V de 32 bits) |
| Memoria de programa | Flash SPI externa de un solo bit (lectura con comando `0x03`) |
| Memoria de datos | RAM SPI externa de un solo bit, en un bus independiente del de la flash |
| Depuración | Interfaz UART |
| Pines `uio[0:7]` | Sin uso en esta configuración |
| Plataforma de prueba | Tiny Tapeout Demo Board v3.2 (RP2040) |

El chip no contiene memoria de programa interna, por lo que todo programa debe ser servido desde una memoria flash SPI externa. Esta característica motiva buena parte del trabajo de emulación de memoria documentado aquí.

---

## Pruebas

| Carpeta | Prueba |
|---------|--------|
| [`fpga/led_blink`](fpga/led_blink) | Flujo Yosys + Gowin en la Tang Primer 20K |
| [`fpga/spi_flash_emu`](fpga/spi_flash_emu) | Emulador de flash SPI en la FPGA, probado con el ESP32-C6 |
| [`docs/mediciones/consumo_ppk2`](docs/mediciones/consumo_ppk2) | Capacidad de corriente del 3V3 de la demo board |
| [`asic/hello_world_uart`](asic/hello_world_uart) | Primer arranque del femto_UN: Hello World por UART |
| [`asic/ram_test`](asic/ram_test) | RAM SPI (FM25V02) con el femto_UN: lectura, escritura y mayúsculas |

Firmware de soporte:

| Carpeta | Contenido |
|---------|-----------|
| [`firmware/esp32_flash_emu`](firmware/esp32_flash_emu) | Emulador de flash SPI en ESP32-C6 que sirve el programa al femto_UN |

---

## Estructura del repositorio

```
ris-v-manizales/
├── README.md
├── fpga/
│   ├── led_blink/          Flujo Yosys + Gowin (prueba base)
│   └── spi_flash_emu/      Esclavo SPI tipo flash NOR en BRAM
├── firmware/
│   └── esp32_flash_emu/    Emulador de flash SPI en ESP32-C6
├── asic/
│   ├── hello_world_uart/   Primer arranque del femto_UN
│   └── ram_test/           Pruebas de RAM SPI con el femto_UN
└── docs/
    └── mediciones/
        └── consumo_ppk2/   Medición de consumo en el riel de 3V3
```

---

## Hardware utilizado

| Equipo | Uso |
|--------|-----|
| Sipeed Tang Primer 20K Dock (GW2A-LV18PG256C8/I7) | Desarrollo FPGA y emulación de flash SPI en BRAM |
| Tiny Tapeout Demo Board v3.2 (RP2040) | Soporte, alimentación y reloj del chip femto_UN |
| Chip femto_UN (Tiny Tapeout) | Dispositivo bajo prueba |
| ESP32-C6-WROOM-1 (StudioPixels) | Maestro SPI de prueba y emulador de flash SPI |
| FM25V02-G (F-RAM SPI, 32 KB) | Memoria RAM externa del femto_UN |
| Adaptador USB-UART (FTDI) | Consola UART del femto_UN |
| Analizador lógico | Captura de los buses SPI y UART |
| Nordic Power Profiler Kit II (PPK2) | Medición de consumo de corriente |
| Programador CH341A | Programación de memorias flash fuera de la placa |
| Analog Discovery 2 | Instrumento previsto para la placa tester |

---

## Herramientas de software

| Herramienta | Función |
|-------------|---------|
| Yosys (oss-cad-suite) | Síntesis lógica |
| Gowin EDA (`gw_sh`) | Place and route y generación de bitstream para GW2A |
| openFPGALoader | Programación de la Tang Primer 20K (compilado desde fuente) |
| Icarus Verilog (`iverilog`, `vvp`) | Simulación RTL |
| GTKWave | Visualización de formas de onda |
| netlistsvg | Generación de diagramas de la netlist |
| `riscv-none-elf-gcc` (xPack) | Compilación cruzada del firmware RISC-V |
| `arduino-cli` | Compilación y carga de firmware en el ESP32-C6 |
| `mpremote` | Consola MicroPython de la demo board |
| `minicom` | Terminal UART |
| KiCad 10.0 | Diseño de la placa tester |
| Sistema operativo | Fedora Linux |

---

## Descripción detallada de las pruebas

### 1. Flujo Yosys + Gowin en la Tang Primer 20K — `fpga/led_blink`

**Objetivo.** Establecer un flujo de implementación automatizado que combine herramientas abiertas (Yosys) para la síntesis con la herramienta del fabricante (Gowin EDA) para el place and route, ejecutable completamente desde línea de comandos en Linux.

**Motivación.** Contar con un flujo reproducible y scriptable permite, a futuro, automatizar la implementación de diseños más complejos, como memorias emuladas u otro procesador (por ejemplo, una segunda versión del femto_UN).

**Procedimiento.**
1. Síntesis del diseño Verilog con Yosys.
2. Place and route con Gowin EDA mediante un script TCL ejecutado con `gw_sh`.
3. Programación de la FPGA con openFPGALoader.

**Resultado.** Diseño sintetizado, implementado y programado correctamente en hardware; LED parpadeando según lo esperado. Reloj de la tarjeta en el pin H11 (27 MHz).

---

### 2. Emulador de flash SPI en FPGA — `fpga/spi_flash_emu`

**Objetivo.** Implementar dentro de la FPGA un esclavo SPI que se comporte como una memoria flash NOR, como alternativa a la memoria de programa física del femto_UN.

**Diseño.**
- Almacenamiento en BRAM de 8 KB, precargado en síntesis desde `rtl/mem_init.hex`.
- Contenido: firmware real de FemtoRV (`firmware_shifted.bin`, 1120 bytes).
- Comando soportado: `READ (0x03)` con dirección de 24 bits.
- Núcleo SPI: `spi_slave_flash.v`.
- Referencia de enfoque: `ArthurHeymans/tang_20k_spi_flash`, adaptado a la Tang Primer 20K Dock (GW2A, sin el bloque SDRAM interno de la Tang Nano 20K).

**Asignación de pines (PMOD0, fila inferior, verificada en la serigrafía de la tarjeta).**

| Señal | Pin FPGA | GPIO ESP32-C6 |
|-------|----------|---------------|
| CS_N | T6 | GPIO7 |
| SCK | T7 | GPIO6 |
| MOSI | T8 | GPIO5 |
| MISO | P9 | GPIO4 |

LED de heartbeat en L14 para confirmar que el diseño está activo.

**Verificación.**
- Simulación en Icarus Verilog con un maestro SPI en el testbench: lectura correcta de los datos de prueba.
- Prueba en hardware con el ESP32-C6 como maestro SPI (sketch `esp32_spi_test.ino`, con verificación por CRC32): lectura correcta desde la flash emulada a través de una conexión SPI real.

**Alcance.** La FPGA no se ha utilizado como flash del femto_UN. Esta prueba valida el emulador únicamente con el ESP32-C6 como maestro; la conexión con el procesador queda como trabajo futuro.

---

### 3. Capacidad de corriente del riel de 3V3 — `docs/mediciones/consumo_ppk2`

**Objetivo.** Determinar el consumo de la demo board con el femto_UN para verificar si el riel de 3V3 puede alimentar los periféricos de la placa tester, como paso previo al diseño del árbol de alimentación.

**Montaje.** PPK2 conectado directamente al pin de 3V3 de un header del ETR; capturas de 10 s.

**Resultados.**

| Condición | Corriente promedio | Corriente pico |
|-----------|-------------------|----------------|
| Código del femto_UN | 68,93 mA | 184,21 mA |
| Firmware de fábrica | 70,00 mA | 255,36 mA |

**Observación.** Los valores cercanos a 184 mA y 250 mA corresponden a picos transitorios, no al consumo promedio.

---

### 4. Primer arranque del femto_UN: Hello World por UART — `asic/hello_world_uart`

**Objetivo.** Verificar que el chip femto_UN arranca, ejecuta código desde una flash SPI externa y transmite datos por UART.

**Montaje.**
- femto_UN en la Tiny Tapeout Demo Board, lanzado desde la consola MicroPython de la demo board.
- Flash SPI emulada en el ESP32-C6 (`firmware/esp32_flash_emu`), debido a que el módulo flash W25QXX disponible presentaba el pin DO en corto con GND.
- UART leída con un adaptador FTDI y `minicom`.
- Analizador lógico en los buses SPI y UART.

**Resultado.** El procesador arrancó, leyó el programa desde la flash emulada y transmitió el mensaje por UART. Las capturas del analizador lógico se encuentran en la carpeta `img/` de la prueba.

---

### 5. RAM SPI con el femto_UN — `asic/ram_test`

**Objetivo.** Validar el acceso del femto_UN a una memoria RAM SPI externa (FM25V02, F-RAM de 32 KB) en lectura y escritura, y construir sobre ella una aplicación sencilla.

**Montaje.** Flash emulada en el ESP32-C6, UART por FTDI y analizador lógico conectado al bus de la RAM.

**Prueba de lectura y escritura.** Salida obtenida en `minicom`:

```
L1 7EFDFCFB
L2 6EEDECEB
E1 00000001 00000002
E2 4ECDCCCB 4ECDCCCB
```

El contador `E1` se incrementa en cada reinicio y su valor se conserva tras desconectar y reconectar la alimentación, comportamiento consistente con la naturaleza no volátil de la F-RAM FM25V02.

**Aplicación de mayúsculas.** Programa que recibe texto por UART, lo almacena en la RAM y lo devuelve convertido a mayúsculas (las minúsculas se convierten y el resto de caracteres se mantiene). La versión `mayus2` funciona de forma estable.

**Observación.** La primera corrida devolvió únicamente ceros; la causa fue una conexión defectuosa del cable de 3V3 de la RAM.

---

## Placa tester femto_UN_tester

Placa de extensión pasiva, sin microcontrolador embebido, diseñada en KiCad 10.0 para caracterizar el femto_UN mediante instrumentación externa (Analog Discovery 2). Se acopla al demoboard ETR mediante tres conectores PMOD macho de 2x6 (J_IN, J_BIR, J_OUT), separados 22,86 mm.

**Arquitectura.**

| Bloque | Contenido |
|--------|-----------|
| Alimentación | Jumper JP1 para medición de corriente, capacitores de desacople, LED indicador y puntos de prueba |
| Flash SPI | Winbond W25Q32JVSSIQ en zócalo SOIC-8 (208 mil) removible, resistencias en serie, pull-up en CS_n, WP/HOLD a 3V3 |
| RAM SPI | FM25V02-G (SOP-8) con el mismo esquema que la flash |
| UART | Header J_UART para convertidor USB-UART externo, LED de estado en `uo6` |
| Expansión | Header J3 hacia el Analog Discovery 2 |

**Criterios de diseño.**
- Buses SPI de flash y RAM independientes, de un solo bit.
- La flash se programa fuera de la placa con un programador externo; no se incluye circuitería de programación.
- Máximo acceso de sonda: puntos de prueba en las señales relevantes.
- Resistencias y capacitores 0603, LEDs 0805, puntos de prueba como header 1x01 de agujero pasante.

**Estado.** Esquemático cerrado sin errores de ERC y diseño de PCB terminado.

---

## Configuración del entorno

### FPGA (Tang Primer 20K)

```bash
# Síntesis, place and route y bitstream
make

# Programación
openFPGALoader -b tangprimer20k build/<proyecto>/impl/pnr/<proyecto>.fs
```

### Firmware del femto_UN

Se utiliza la toolchain precompilada xPack, ya que el paquete `gcc-riscv32-linux-gnu` de Fedora no incluye sysroot:

```bash
export PATH=$HOME/riscv-toolchain/bin:$PATH
make CROSS=riscv-none-elf
```

### ESP32-C6

```bash
arduino-cli compile --fqbn esp32:esp32:esp32c6 firmware/esp32_flash_emu
arduino-cli upload  -p /dev/ttyACM0 --fqbn esp32:esp32:esp32c6 firmware/esp32_flash_emu
```

### Ejecución en la demo board

```bash
# Consola de la demo board
mpremote connect /dev/ttyACM0
```

```python
# En el REPL
FREQ=100000; exec(open('femto_setup.py').read())
```

```bash
# Consola UART del femto_UN
sudo minicom -b 481 -D /dev/ttyUSB0
```

---

## Problemas encontrados y soluciones

| Problema | Solución |
|----------|----------|
| `cells_sim.v` de oss-cad-suite con inclusión duplicada en Fedora | Copia local corregida del archivo |
| Gowin cambia el directorio de trabajo al ejecutar `create_project` | Capturar el directorio con `[pwd]` antes y usar rutas absolutas en `add_file` |
| Toolchain RISC-V de Fedora sin sysroot (`stdint.h` ausente) | Uso de `riscv-none-elf-gcc` de xPack con `CROSS=riscv-none-elf` |
| Módulo flash W25QXX con el pin DO en corto a GND | Emulación de la flash en el ESP32-C6 |
| `femto_setup.py` falla con `AttributeError` y avisos de contención | Desconectar las señales del ESP32 y del FTDI de `ui_in0`/`ui_in2` durante el arranque |
| Lectura de la RAM en ceros | Corrección de la conexión de 3V3 de la RAM |
| Asignación de pines PMOD de la Tang Primer 20K incierta | Verificación sobre la serigrafía de la tarjeta en lugar del esquemático |

---

## Estado actual y trabajo futuro

**Completado.**
- Flujo Yosys + Gowin automatizado y funcional.
- Emulador de flash SPI en FPGA validado con el ESP32-C6.
- Emulador de flash SPI en ESP32-C6 funcionando con el femto_UN.
- Arranque del femto_UN y comunicación por UART.
- Lectura y escritura de RAM SPI y aplicación de mayúsculas.
- Medición de consumo del riel de 3V3.
- Diseño de la placa tester en KiCad.

**Pendiente.**
- Conectar el emulador de flash en FPGA como memoria de programa del femto_UN.
- Fabricación, ensamble y validación de la placa tester.
- Definición final del header J3 hacia el Analog Discovery 2.
- Simulación post-layout del femto_UN con el flujo local de Tiny Tapeout (LibreLane, PDK sky130A).
- Emulación en FPGA de memorias adicionales y de una segunda versión del procesador.

---

## Referencias

- [cicamargoba/femto_UN](https://github.com/cicamargoba/femto_UN) — Repositorio del procesador femto_UN.
- [cicamargoba/VLSI](https://github.com/cicamargoba/VLSI) — Material del curso, incluyendo la simulación RTL en `tinytapeout/`.
- [ArthurHeymans/tang_20k_spi_flash](https://github.com/ArthurHeymans/tang_20k_spi_flash) — Emulador de flash SPI para Tang Nano 20K, base del enfoque en FPGA.
- [BrunoLevy/learn-fpga](https://github.com/BrunoLevy/learn-fpga) — Proyecto FemtoRV32.
- [Tiny Tapeout](https://tinytapeout.com) — Programa de fabricación del chip.
- Sipeed, documentación de la Tang Primer 20K.
- Winbond, hoja de datos W25Q32JV.
- Infineon (Cypress), hoja de datos FM25V02.

---

