# Toolchain y entorno de trabajo

Guía para montar desde cero el entorno usado en todas las pruebas del repo.

**Sistema operativo:** Fedora Linux (versión: TODO)
**Editor:** VS Code

## Resumen de herramientas

| Herramienta | Uso | Ubicación |
|-------------|-----|-----------|
| oss-cad-suite (Yosys, Icarus Verilog, GTKWave) | Síntesis y simulación | `~/fpga-tools/oss-cad-suite/` |
| Gowin EDA (`gw_sh`) | Place & route para Tang Primer 20K | TODO |
| openFPGALoader | Programar la FPGA | Compilado desde fuente |
| netlistsvg | Diagramas del netlist | npm global |
| xPack `riscv-none-elf-gcc` | Firmware bare-metal femtoRV32 | `~/riscv-toolchain` |
| KiCad 10.0 | Diseño de PCB | TODO |

## 1. oss-cad-suite

TODO: comando de descarga y descompresión (versión usada: TODO)

Agregar al PATH en `~/.bashrc`:

```bash
export PATH="$HOME/fpga-tools/oss-cad-suite/bin:$PATH"
```

###  Problema: include duplicado en `cells_sim.v`
En Fedora, el `cells_sim.v` de oss-cad-suite tiene un include duplicado que rompe la simulación.
**Solución:** usar una copia local parcheada. TODO: indicar qué línea se quitó y dónde se guarda la copia.

###  Nota: `yosys-config` puede no existir
Aunque Yosys esté instalado, `yosys-config` puede faltar. No es necesario para los flujos de este repo.

## 2. Gowin EDA

TODO: de dónde se descargó, versión, licencia y ruta de instalación.

### Problemas con el scripting TCL
- `create_project` cambia el directorio de trabajo: guardar el directorio con `[pwd]` **antes** de llamarlo.
- Usar rutas absolutas en todos los `add_file`.
- El bitstream queda en `build/<proyecto>/impl/pnr/`.

## 3. openFPGALoader

Compilado desde el código fuente.

TODO: dependencias instaladas con `dnf` y comandos de compilación.

TODO: regla udev / permisos USB si fue necesaria.

## 4. netlistsvg (Node.js)

Para evitar errores de permisos con `npm install -g`, usar un prefijo local:

```bash
mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global
export PATH="$HOME/.npm-global/bin:$PATH"   # agregar a ~/.bashrc
npm install -g netlistsvg
```

## 5. Toolchain RISC-V

El paquete de Fedora `gcc-riscv32-linux-gnu` **no sirve**: no trae sysroot (falta `stdint.h`, etc.).

Se usa el toolchain precompilado de xPack:

TODO: URL y versión descargada.

```bash
export PATH="$HOME/riscv-toolchain/bin:$PATH"   # TODO: verificar ruta exacta de bin/
```

Los Makefiles del curso usan `riscv64-unknown-elf` por defecto, así que se invocan con:

```bash
make CROSS=riscv-none-elf
```

## 6. Otros

- **Chrome como Flatpak:** necesita permisos explícitos de acceso al sistema de archivos (TODO: comando o Flatseal).

## Verificación rápida

```bash
yosys -V
iverilog -V
openFPGALoader --Version
riscv-none-elf-gcc --version
netlistsvg --version
```