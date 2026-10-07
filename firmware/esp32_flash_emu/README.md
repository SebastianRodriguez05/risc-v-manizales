# esp32_flash_emu — ESP32-C6 como memoria flash SPI del femto_UN

Sketch de Arduino para **ESP32-C6** que hace de memoria flash SPI de solo lectura. El femto_UN (`tt_um_femto`) lee de aquí su programa.

Prueba principal y conexiones: [`asic/hello_world_uart`](../../asic/hello_world_uart).

## Qué hace

- Espera a que `CS` baje y lee el comando por `MOSI` (SPI modo 0).
- Si el comando es **READ (0x03)**, lee los 24 bits de dirección y entrega los bytes del firmware por `MISO` mientras `CS` siga en bajo.
- **Cualquier otro comando se ignora** y `MISO` queda en alto, igual que en una flash real. Fuera del firmware responde `FF`, como una flash borrada.
- Guarda las últimas 32 transacciones para depurar.

Las dos reglas en negrita no son un detalle: el femto_UN las necesita para arrancar. La explicación está en la prueba principal.

## Pines

| Señal | GPIO | Va a (demo board) |
|-------|------|-------------------|
| CS | 7 | `uo[2]` |
| SCK | 6 | `uo[5]` |
| MOSI | 5 | `uo[0]` |
| MISO | 4 | `ui[0]` |
| GND | GND | GND |

## Uso

1. Generar `firmware.h` a partir del binario **con corrimiento**:
   ```bash
   xxd -i firmware_shifted.bin > firmware.h
   ```
   El nombre del arreglo debe quedar `firmware_shifted_bin`.
2. Compilar y cargar:
   ```bash
   arduino-cli compile --fqbn esp32:esp32:esp32c6 .
   arduino-cli upload -p /dev/ttyACM1 --fqbn esp32:esp32:esp32c6 .
   ```
3. Monitor serie a **115200 baudios**, sin tocar las líneas de reset:
   ```bash
   arduino-cli monitor -p /dev/ttyACM1 -c baudrate=115200 -c dtr=off -c rts=off
   ```

Al arrancar imprime el tamaño del firmware y sus primeros 4 bytes (`1B 81 A0 00` con `uart_full_demo`).

## Registro de transacciones

Con el femto **en reset** (`CS` quieto en alto), escribir `p` + Enter imprime el resumen y las últimas 32 transacciones; `c` + Enter borra los contadores. Mientras el femto corre, el sketch no atiende el monitor para no perder flancos.

- `READ`: comando `03` atendido, con su dirección y cuántos bytes se enviaron.
- `ignorado`: llegó otro comando. Ver `06` aquí es normal: son las lecturas que el femto emite con el primer bit perdido.
- `incompleta`: `CS` subió antes de completar el comando.

## Limitaciones

- El SPI se atiende **por software**, leyendo los pines en un bucle. Sirve con el reloj del femto en ~100 kHz (SPI a ~33 kHz), no a los 24 MHz del chip.
- Enchufar **primero la demo board** y después el ESP32. Con el ESP32 encendido antes, la demo board arrancó en modo BOOT; la causa probable es que `MISO` en alto le mete voltaje al RP2350 por `ui[0]`.
