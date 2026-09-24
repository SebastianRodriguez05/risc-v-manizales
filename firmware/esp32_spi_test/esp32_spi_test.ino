#include <SPI.h>

#define PIN_SCK  6
#define PIN_MISO 4
#define PIN_MOSI 5
#define PIN_CS   7

#define PROGRAM_SIZE 1120  // tamano real de firmware_shifted.bin

SPIClass *spi = NULL;
uint8_t buf[PROGRAM_SIZE];

uint32_t crc32_update(uint32_t crc, uint8_t data) {
  crc ^= data;
  for (int i = 0; i < 8; i++) {
    if (crc & 1) crc = (crc >> 1) ^ 0xEDB88320;
    else crc >>= 1;
  }
  return crc;
}

uint32_t compute_crc32(uint8_t *data, size_t len) {
  uint32_t crc = 0xFFFFFFFF;
  for (size_t i = 0; i < len; i++) crc = crc32_update(crc, data[i]);
  return crc ^ 0xFFFFFFFF;
}

void setup() {
  Serial.begin(115200);
  delay(2000);

  pinMode(PIN_CS, OUTPUT);
  digitalWrite(PIN_CS, HIGH);

  spi = new SPIClass(FSPI);
  spi->begin(PIN_SCK, PIN_MISO, PIN_MOSI, -1);

  Serial.println("ESP32-C6 listo. Leyendo programa completo...");
}

void loop() {
  SPISettings settings(1000000, MSBFIRST, SPI_MODE0);

  unsigned long t0 = millis();

  digitalWrite(PIN_CS, LOW);
  spi->beginTransaction(settings);

  spi->transfer(0x03); // comando READ
  spi->transfer(0x00);
  spi->transfer(0x00);
  spi->transfer(0x00); // direccion 0x000000

  for (int i = 0; i < PROGRAM_SIZE; i++) {
    buf[i] = spi->transfer(0x00);
  }

  spi->endTransaction();
  digitalWrite(PIN_CS, HIGH);

  unsigned long elapsed = millis() - t0;

  uint32_t crc = compute_crc32(buf, PROGRAM_SIZE);

  Serial.printf("Leidos %d bytes en %lu ms\n", PROGRAM_SIZE, elapsed);
  Serial.print("Primeros bytes: ");
  for (int i = 0; i < 8; i++) Serial.printf("%02X ", buf[i]);
  Serial.println();
  Serial.print("Ultimos bytes:  ");
  for (int i = PROGRAM_SIZE - 8; i < PROGRAM_SIZE; i++) Serial.printf("%02X ", buf[i]);
  Serial.println();
  Serial.printf("CRC32: 0x%08X\n", crc);
  Serial.println("Contenido legible (bytes imprimibles):");
  for (int i = 0; i < PROGRAM_SIZE; i++) {
    if (buf[i] >= 32 && buf[i] <= 126) Serial.write(buf[i]);
    else if (buf[i] == '\n' || buf[i] == '\r') Serial.write(buf[i]);
  }
  Serial.println();
  Serial.println("-----");

  delay(3000);
}
