/*
 * Emulador de flash SPI (solo lectura) en ESP32-C6 para el femto_UN (tt_um_femto).
 *
 * Se comporta como una flash real: solo responde al comando READ (0x03) y deja
 * MISO en alto el resto del tiempo. Las dos cosas son necesarias para que el
 * femto_UN arranque (ver asic/hello_world_uart/README.md):
 *   - Las lecturas que llegan con el primer bit perdido (se ven como 0x06) se
 *     ignoran; el femto lee FFFFFFFF, salta hacia atras y reinicia desde 0.
 *   - MISO en alto en reposo evita que el femto lea 00000000 y se quede en bucle.
 *
 * firmware.h:  xxd -i firmware_shifted.bin > firmware.h
 * Conexiones:  uo[2] CS -> GPIO7, uo[5] CLK -> GPIO6, uo[0] MOSI -> GPIO5,
 *              ui[0] MISO <- GPIO4, GND comun.
 * El SPI se atiende por software: usar el reloj del femto a ~100 kHz.
 * Monitor serie (115200): p + Enter = ver transacciones, c + Enter = borrar.
 *   (solo responde con el femto en reset, es decir, con CS quieto en alto)
 */
#include "soc/gpio_reg.h"
#include "firmware.h"

#define PIN_MISO 4
#define PIN_MOSI 5
#define PIN_SCK  6
#define PIN_CS   7
#define M_CS   (1UL << PIN_CS)
#define M_SCK  (1UL << PIN_SCK)
#define M_MOSI (1UL << PIN_MOSI)
#define M_MISO (1UL << PIN_MISO)

static inline uint32_t rd() { return REG_READ(GPIO_IN_REG); }
static inline void miso(uint32_t bit) {
  if (bit) REG_WRITE(GPIO_OUT_W1TS_REG, M_MISO);
  else     REG_WRITE(GPIO_OUT_W1TC_REG, M_MISO);
}
// Fuera del firmware responde FF, igual que un flash borrado
static inline uint8_t mem(uint32_t a) {
  return a < firmware_shifted_bin_len ? firmware_shifted_bin[a] : 0xFF;
}
static inline bool wait_rise(uint32_t &v) {
  do { v = rd(); if (v & M_CS) return false; } while (!(v & M_SCK));
  return true;
}
static inline bool wait_fall() {
  uint32_t v;
  do { v = rd(); if (v & M_CS) return false; } while (v & M_SCK);
  return true;
}
// Un bit: espera subida (muestrea MOSI) y luego bajada. -1 si CS sube antes.
static inline int rx_bit() {
  uint32_t v;
  if (!wait_rise(v)) return -1;
  int b = (v & M_MOSI) ? 1 : 0;
  wait_fall();
  return b;
}
static bool tx_byte(uint8_t b) {
  uint32_t v;
  for (int i = 7; i >= 0; i--) {
    miso((b >> i) & 1);
    if (!wait_rise(v)) return false;
    if (!wait_fall()) return false;
  }
  return true;
}

// ---------------- Registro ----------------
// modo: 0 = READ atendido, 3 = comando ignorado (no es 0x03), 4 = incompleta
struct Entry { uint8_t cmd; uint8_t modo; uint32_t addr; uint32_t n; };
#define LOGN 32
static Entry logbuf[LOGN];
static uint32_t nlog = 0, ntrans = 0, nmodo[5] = {0};
static const char *NOMBRE[5] = {"READ", "-", "-", "ignorado", "incompleta"};
static void logit(uint8_t cmd, uint8_t modo, uint32_t addr, uint32_t n) {
  logbuf[nlog % LOGN] = {cmd, modo, addr, n}; nlog++; nmodo[modo]++;
}
static void dump() {
  Serial.printf("\nTransacciones: %lu | READ=%lu ignorados=%lu incompletas=%lu\n",
                (unsigned long)ntrans, (unsigned long)nmodo[0], (unsigned long)nmodo[3],
                (unsigned long)nmodo[4]);
  uint32_t first = nlog > LOGN ? nlog - LOGN : 0;
  for (uint32_t i = first; i < nlog; i++) {
    Entry &e = logbuf[i % LOGN];
    Serial.printf("#%lu  cmd=%02X  %-13s addr=0x%06lX  bytes=%lu\n", (unsigned long)i, e.cmd,
                  NOMBRE[e.modo], (unsigned long)e.addr, (unsigned long)e.n);
  }
}

static void transaction() {
  // Pausa de ~1 us: si CS y CLK cambiaron a la vez, esperar a que CLK quede estable
  for (volatile int i = 0; i < 16; i++) (void)rd();
  uint32_t bits = 0;
  for (int i = 0; i < 8; i++) {
    int b = rx_bit();
    if (b < 0) { logit(bits, 4, 0, 0); return; }
    bits = (bits << 1) | b;
  }
  // Igual que un flash real: solo responde a READ (0x03). Cualquier otra cosa se ignora
  // y MISO queda en alto. El femto NECESITA que las lecturas con el bit corrido fallen.
  if (bits != 0x03) { logit(bits, 3, 0, 0); return; }
  uint32_t a = 0;
  for (int i = 0; i < 24; i++) {
    int b = rx_bit();
    if (b < 0) { logit(0x03, 4, a, 0); return; }
    a = (a << 1) | (uint32_t)b;
  }
  uint32_t start = a, n = 0;
  while (tx_byte(mem(a))) { a = (a + 1) & 0x7FFFFF; n++; }
  logit(0x03, 0, start, n);
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_CS, INPUT_PULLUP); pinMode(PIN_SCK, INPUT); pinMode(PIN_MOSI, INPUT);
  pinMode(PIN_MISO, OUTPUT); digitalWrite(PIN_MISO, HIGH);
  delay(1500);
  Serial.printf("\nEmulador de flash listo: %u bytes\n", firmware_shifted_bin_len);
  Serial.printf("Primeros bytes: %02X %02X %02X %02X\n", mem(0), mem(1), mem(2), mem(3));
  Serial.println("p + Enter = ver transacciones, c + Enter = borrar.");
}

void loop() {
  static uint32_t idle = 0;
  if (rd() & M_CS) {
    // Solo se atiende el monitor serie con el femto quieto (en reset), para no perder flancos
    if (++idle > 400000) {
      idle = 400000;
      if (Serial.available()) {
        int c = Serial.read();
        if (c == 'p') dump();
        else if (c == 'c') { nlog = ntrans = 0; for (int i = 0; i < 5; i++) nmodo[i] = 0; Serial.println("Borrado"); }
      }
    }
    return;
  }
  idle = 0;
  ntrans++;
  transaction();
  while (!(rd() & M_CS)) {}
  miso(1);                                 // MISO en alto en reposo (lo necesita el femto)
}
