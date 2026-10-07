#!/usr/bin/env python3
"""
Prueba básica de flash SPI (Winbond W25Q32JV) con el programador CH341A.

Genera transacciones SPI cortas y separadas en el tiempo para verlas
cómodamente en un analizador lógico (CS, SCK, MOSI, MISO).

Solo usa comandos de LECTURA, no modifica el contenido del flash:
  0x9F  JEDEC ID           -> W25Q32JV responde EF 40 16
  0x05  Status Register 1  -> normalmente 00
  0x03  Read Data (dir. 24 bits) -> en un chip nuevo, todo FF

Requisitos:  pip install pyusb   (y libusb instalado en el sistema)

Uso:
  python3 ch341a_spi_test.py                 # una pasada de las 3 pruebas
  python3 ch341a_spi_test.py --loop          # repite hasta Ctrl+C
  python3 ch341a_spi_test.py --loop --delay 1 --n 8 --addr 0x000100
"""
import sys
import time
import argparse

import usb.core
import usb.util

# ---------------- Protocolo USB del CH341A (mismo que usa flashrom) ----------------
VID, PID = 0x1A86, 0x5512
EP_OUT, EP_IN = 0x02, 0x82
PKT = 32                      # tamaño de paquete USB; 1 byte es el comando

CMD_SPI_STREAM = 0xA8
CMD_I2C_STREAM = 0xAA         # también configura la velocidad del SPI
CMD_UIO_STREAM = 0xAB         # control directo de pines D0..D5

I2C_STM_SET = 0x60
I2C_STM_END = 0x00
UIO_STM_OUT = 0x80
UIO_STM_DIR = 0x40
UIO_STM_END = 0x20

# Pines del CH341A en modo SPI: D0=CS, D3=SCK, D5=MOSI, D7=MISO (entrada)
PINS_IDLE = 0x37              # CS=1 (inactivo), SCK=0  -> modo SPI 0
PINS_CS_LOW = 0x36            # CS=0 (activo),   SCK=0


def rev(b):
    """El CH341A transmite LSB primero; el flash espera MSB primero -> invertir bits."""
    return int(f"{b:08b}"[::-1], 2)


def hexs(data):
    return " ".join(f"{x:02X}" for x in data)


class CH341A:
    def __init__(self, speed=1):
        dev = usb.core.find(idVendor=VID, idProduct=PID)
        if dev is None:
            sys.exit("No se encontró el CH341A (1a86:5512). Revisa la conexión con `lsusb`.")
        try:
            if dev.is_kernel_driver_active(0):
                dev.detach_kernel_driver(0)
        except (NotImplementedError, usb.core.USBError):
            pass
        try:
            dev.set_configuration()
        except usb.core.USBError as e:
            sys.exit(f"Error USB: {e}\nSi es de permisos, prueba con sudo o agrega una regla udev "
                     "(ver instrucciones).")
        self.dev = dev
        # Velocidad del stream (0..3; flashrom usa 1)
        self._w([CMD_I2C_STREAM, I2C_STM_SET | (speed & 0x7), I2C_STM_END])
        # D0..D5 como salidas, CS en alto
        self._w([CMD_UIO_STREAM, UIO_STM_OUT | PINS_IDLE, UIO_STM_DIR | 0x3F, UIO_STM_END])

    def _w(self, data):
        self.dev.write(EP_OUT, bytes(data), timeout=1000)

    def _r(self, n):
        buf = bytearray()
        while len(buf) < n:
            buf += bytes(self.dev.read(EP_IN, n - len(buf), timeout=1000))
        return bytes(buf)

    def cs(self, active):
        self._w([CMD_UIO_STREAM,
                 UIO_STM_OUT | (PINS_CS_LOW if active else PINS_IDLE),
                 UIO_STM_END])

    def xfer(self, tx):
        """Transferencia full-duplex: por cada byte enviado por MOSI se recibe uno por MISO."""
        rx = bytearray()
        for i in range(0, len(tx), PKT - 1):
            chunk = tx[i:i + PKT - 1]
            self._w([CMD_SPI_STREAM] + [rev(b) for b in chunk])
            rx += bytes(rev(b) for b in self._r(len(chunk)))
        return bytes(rx)

    def transaction(self, tx):
        """CS baja -> bytes -> CS sube. Una transacción = una ventana de CS en el analizador."""
        self.cs(True)
        rx = self.xfer(list(tx))
        self.cs(False)
        return rx

    def close(self):
        # Deja los pines en alta impedancia
        self._w([CMD_UIO_STREAM, UIO_STM_OUT | PINS_IDLE, UIO_STM_DIR | 0x00, UIO_STM_END])
        usb.util.dispose_resources(self.dev)


# ---------------- Pruebas ----------------
def test_jedec(f):
    tx = [0x9F, 0x00, 0x00, 0x00]
    rx = f.transaction(tx)
    mid, typ, cap = rx[1], rx[2], rx[3]
    ok = (mid, typ, cap) == (0xEF, 0x40, 0x16)
    print(f"[9F JEDEC ID ] MOSI: {hexs(tx)}")
    print(f"               MISO: {hexs(rx)}  -> {mid:02X} {typ:02X} {cap:02X} "
          f"{'OK (Winbond W25Q32JV)' if ok else '(esperado EF 40 16)'}")
    if (mid, typ, cap) in [(0xFF, 0xFF, 0xFF), (0x00, 0x00, 0x00)]:
        print("               ! MISO fijo en FF/00: revisa conexión, orientación del chip o VCC.")


def test_status(f):
    tx = [0x05, 0x00]
    rx = f.transaction(tx)
    sr = rx[1]
    print(f"[05 STATUS 1 ] MOSI: {hexs(tx)}")
    print(f"               MISO: {hexs(rx)}  -> SR1={sr:02X} "
          f"(BUSY={sr & 1}, WEL={(sr >> 1) & 1}, BP={(sr >> 2) & 7})")


def test_read(f, addr, n):
    tx = [0x03, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF] + [0x00] * n
    rx = f.transaction(tx)
    data = rx[4:]
    print(f"[03 READ     ] MOSI: {hexs(tx[:4])} + {n} x 00   (dir 0x{addr:06X})")
    print(f"               MISO: {hexs(data)}")
    if all(b == 0xFF for b in data):
        print("               (todo FF: zona borrada, normal en un chip nuevo)")


def test_compare(f, path, addr):
    """Lee len(archivo) bytes del flash en UNA transacción (un solo CS) y compara."""
    ref = open(path, "rb").read()
    n = len(ref)
    tx = [0x03, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF] + [0x00] * n
    t0 = time.time()
    rx = f.transaction(tx)
    dt = time.time() - t0
    data = rx[4:]
    print(f"[03 COMPARE  ] {path}: {n} bytes desde 0x{addr:06X}  ({dt*1000:.0f} ms)")
    print(f"               archivo: {hexs(ref[:16])}")
    print(f"               flash  : {hexs(data[:16])}")
    errs = [i for i in range(n) if data[i] != ref[i]]
    if not errs:
        print(f"               OK: los {n} bytes coinciden")
    else:
        print(f"               FALLA: {len(errs)} bytes distintos. Primeros:")
        for i in errs[:10]:
            print(f"                 0x{addr + i:06X}: archivo={ref[i]:02X} flash={data[i]:02X}")
    return not errs


def main():
    ap = argparse.ArgumentParser(description="Prueba SPI de flash con CH341A para analizador lógico")
    ap.add_argument("--compare", metavar="ARCHIVO",
                    help="leer el flash y compararlo con ARCHIVO (p. ej. firmware_shifted.bin)")
    ap.add_argument("--loop", action="store_true", help="repetir hasta Ctrl+C")
    ap.add_argument("--delay", type=float, default=0.5, help="pausa entre transacciones (s)")
    ap.add_argument("--n", type=int, default=16, help="bytes a leer con 0x03")
    ap.add_argument("--addr", type=lambda s: int(s, 0), default=0x000000, help="dirección de lectura")
    ap.add_argument("--speed", type=int, default=1, choices=range(4), help="velocidad CH341A (0..3)")
    args = ap.parse_args()

    f = CH341A(args.speed)
    if args.compare:
        try:
            test_jedec(f)
            ok = test_compare(f, args.compare, args.addr)
        finally:
            f.close()
        sys.exit(0 if ok else 1)
    try:
        ciclo = 0
        while True:
            ciclo += 1
            print(f"\n=== Ciclo {ciclo} ===")
            test_jedec(f)
            time.sleep(args.delay)
            test_status(f)
            time.sleep(args.delay)
            test_read(f, args.addr, args.n)
            if not args.loop:
                break
            time.sleep(args.delay * 2)
    except KeyboardInterrupt:
        print("\nDetenido.")
    finally:
        f.close()


if __name__ == "__main__":
    main()
