# esp32_spi_test — Maestro SPI para probar el emulador de flash

Sketch de Arduino para **ESP32-C6** que lee el contenido del emulador de flash SPI en la FPGA y verifica su integridad con CRC32.

Prueba principal y conexiones: [`fpga/spi_flash_emu`](../../fpga/spi_flash_emu).

## Qué hace

Cada 3 segundos:
1. Baja `CS` y envía el comando **READ (0x03)** con dirección `0x000000`.
2. Lee **1120 bytes** en una sola transacción (SPI modo 0, 1 MHz).
3. Imprime por el monitor serial:
   - tiempo de lectura
   - primeros y últimos 8 bytes
   - **CRC32** del contenido
   - los caracteres imprimibles, para identificar el programa a simple vista

## Pines

| Señal | GPIO |
|-------|------|
| SCK | 6 |
| MISO | 4 |
| MOSI | 5 |
| CS | 7 (controlado manualmente) |

## Uso

1. Abrir `esp32_spi_test.ino` en el Arduino IDE con el soporte de placas ESP32 instalado.
2. Seleccionar la placa ESP32-C6 y el puerto correspondiente, y cargar.
3. Abrir el monitor serial a **115200 baudios**.

Si se cambia el programa cargado en la FPGA, hay que actualizar `PROGRAM_SIZE` con el tamaño del nuevo `.bin`.

## Resultado esperado

Con el contenido actual de `mem_init.hex`, el CRC32 debe ser **`0xE5ABF8F0`**.