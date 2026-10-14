# mayus.S - El femto_UN (tt_um_femto) recibe texto por la UART, lo guarda en la RAM SPI
# (F-RAM FM25V02) y al recibir Enter lo lee de la RAM y lo devuelve en mayusculas.
#
#   - Cada caracter recibido se muestra (eco) y se guarda en la RAM, uno por posicion.
#   - Con Enter (CR o LF) recorre la RAM, convierte a..z en A..Z y deja igual todo lo demas.
#   - Maximo 63 caracteres por linea; al llegar a 63 responde solo.
#
# Mapa: 0x00400008 dato UART, 0x00400010 control/estado UART, 0x0001xxxx RAM SPI.
#   estado UART: bit 9 = transmisor ocupado, bit 8 = llego un dato
#   control UART: 8 = enviar, 1 = dato recibido atendido
#
# Donde queda cada caracter: el numero i se guarda con 'sb' en RAM + i*0x400 + 2. Esta RAM
# solo usa los bits 15..8 de la direccion, asi que caen cada 4 bytes de la F-RAM.
#
# WREN: la FM25V02 exige el comando 06 antes de cada escritura y el femto no lo envia. Antes
# de cada 'sb' se hace un 'lw' en fase mala a proposito: pierde el primer bit y la RAM lo
# recibe como 06.
#
# PAD: cada 'slli zero,zero,2' adelanta 3 pasos la fase del reloj de la RAM (clk/11). Los
# valores salieron de la simulacion ciclo a ciclo: el 'lw' que hace de WREN cae en fase 8 y
# las escrituras y lecturas reales en fase 0. Las instrucciones normales y la UART no mueven
# la fase; si se cambian los accesos a la RAM hay que recalcular los PAD.
#
# No usa x31/t6: un fetch fallido se ejecuta como 'jal x31,-2'.

.macro PAD n
    .rept \n
    slli zero, zero, 2
    .endr
.endm

    .section .text
    .globl _start
_start:
    lui  s0, 0x400
    addi s1, s0, 0x10         # s1 = control/estado de la UART
    addi s0, s0, 0x08         # s0 = dato de la UART
    lui  s4, 0x10             # s4 = 0x00010000, base de la RAM
    addi s8, zero, 0x400      # s8 = separacion entre caracteres
    lui  t0, 0x10
    addi t0, t0, -0x400
    add  s9, s4, t0           # s9 = RAM + 63*0x400 (limite de la linea)
    PAD  9

nueva:
    li   a1,  13        # '\r'
    jal  ra, putc
    li   a1,  10        # '\n'
    jal  ra, putc
    li   a1,  62        # '>'
    jal  ra, putc
    li   a1,  32        # ' '
    jal  ra, putc
    mv   s7, s4               # s7 = donde va el siguiente caracter

# ---- recibir, mostrar y guardar ----
leer:
    lw   t0, 0(s1)
    andi t0, t0, 0x100        # llego un dato?
    beqz t0, leer
    lw   a1, 0(s0)            # leer el caracter
    li   t0, 1
    sw   t0, 0(s1)            # avisar que ya se atendio
    sw   zero, 0(s1)
    andi a1, a1, 0xFF
    li   t0, 13
    beq  a1, t0, responder    # Enter (CR)
    li   t0, 10
    beq  a1, t0, responder    # Enter (LF)
    jal  ra, putc             # eco
    PAD  6
    lw   t0, 0(s7)            # A PROPOSITO en fase mala: la F-RAM recibe 06 = WREN
    PAD  7
    sb   a1, 2(s7)            # guardar el caracter en la RAM
    add  s7, s7, s8
    bne  s7, s9, leer

# ---- leer de la RAM y devolver en mayusculas ----
responder:
    li   a1,  13        # '\r'
    jal  ra, putc
    li   a1,  10        # '\n'
    jal  ra, putc
    beq  s7, s4, nueva        # linea vacia
    mv   s10, s4
    PAD  0
sacar:
    PAD  7
    lbu  a1, 2(s10)           # leer el caracter de la RAM
    li   t0, 97
    blt  a1, t0, 1f           # menor que 'a': se deja igual
    li   t0, 123
    bge  a1, t0, 1f           # mayor que 'z': se deja igual
    addi a1, a1, -32          # minuscula -> mayuscula
1:  jal  ra, putc
    add  s10, s10, s8
    bne  s10, s7, sacar
    PAD  0
    j    nueva

# ---- putc: envia a1 por la UART ----
putc:
    lw   t4, 0(s1)
    andi t4, t4, 0x200        # transmisor ocupado?
    bnez t4, putc
    sw   a1, 0(s0)
    li   t4, 8
    sw   t4, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    ret

    .word 0
