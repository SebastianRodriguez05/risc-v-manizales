# mayus2.S - El femto_UN (tt_um_femto) recibe texto por la UART, lo guarda en la RAM SPI
# (F-RAM FM25V02) y al recibir Enter lo lee de la RAM y lo devuelve en mayusculas.
# Version que se recupera sola de los fallos de la flash y de la RAM.
#
#   - Cada caracter recibido se muestra (eco) y se guarda en la RAM.
#   - Con Enter (CR o LF) recorre la RAM, convierte a..z en A..Z y deja igual lo demas.
#   - Maximo 50 caracteres por linea; al llegar a 50 responde solo.
#
# Mapa: 0x00400008 dato UART, 0x00400010 control/estado UART, 0x0001xxxx RAM SPI.
#   estado UART: bit 9 = transmisor ocupado, bit 8 = llego un dato
#   control UART: 8 = enviar, 1 = dato recibido atendido
#
# POR QUE ESTA ESCRITO ASI
#
# 1) La flash a veces no atiende un fetch. El femto lee entonces FFFFFFFF, que ejecuta como
#    'jal x31,-2'. El efecto alterna: una vez solo reintenta, y la siguiente ejecuta ademas la
#    instruccion que esta justo ANTES en memoria. Para que eso no haga dano:
#      - ninguna instruccion escribe un registro que tambien lee (repetirla da lo mismo);
#      - antes de cada etiqueta hay un 'nop' (si se cuela una instruccion, es ese nop);
#      - no hay subrutinas (repetir un 'jal' repetiria toda la llamada);
#      - no se usa x31/t6.
#
# 2) El reloj SPI de la RAM (clk/11) nunca para. Si CS baja con ese reloj en alto se pierde el
#    primer bit: la RAM ve 06 (WREN) en vez de 03 y 04 en vez de 02. Los PAD ('slli zero,zero,2',
#    201 ciclos en vez de 198) adelantan esa fase 3 pasos cada uno. El 'lw' que hace de WREN
#    debe caer en fase 8 y la escritura y la lectura en fase 0.
#
# 3) Una instruccion repetida mueve esa fase y todo lo que sigue quedaria desalineado. Por eso
#    nada se da por hecho:
#      - al guardar, se relee y se compara; si no coincide, se corre la fase un paso y se repite;
#      - cada caracter se guarda en 4 bytes iguales ('sb' con desplazamiento 3) y al leer se
#        exige que dos de ellos coincidan; si no, se corre la fase un paso y se repite.
#    Asi el programa encuentra solo la fase correcta, sin importar como haya quedado.
#
# Donde queda cada caracter: el numero i va en RAM + i*0x500. Esta RAM solo usa los bits 15..8
# de la direccion, asi que cada uno ocupa 5 bytes de la F-RAM.

.equ INTENTOS, 24

.macro PAD n
    .rept \n
    slli zero, zero, 2
    .endr
.endm

    .section .text
    .globl _start
_start:
    lui  t0, 0x400
    addi s1, t0, 0x10         # s1 = control/estado de la UART
    addi s0, t0, 0x08         # s0 = dato de la UART
    lui  s4, 0x10             # s4 = 0x00010000, base de la RAM
    addi s8, zero, 0x500      # s8 = separacion entre caracteres
    lui  t0, 0x10
    addi t1, t0, -0x600
    add  s9, s4, t1           # s9 = RAM + 50*0x500 (limite de la linea)
    PAD  9

    nop
nueva:
# ---- calibrar: guardar y comprobar una letra de prueba en la posicion 50 ----
# (deja la fase de la RAM ajustada antes de mostrar el '>')
    addi s7, s9, 0
    li   a2, 0x5A
    add  t1, a2, a2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1           # t2 = 256 * caracter
    add  a3, t2, a2         # a3 = caracter repetido en dos bytes
    li   a4, INTENTOS
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # esperar a que la UART termine de enviar
    bnez t5, 1b
    PAD  6
    nop
guardar_cal:
    lw   t0, 0(s7)            # A PROPOSITO en fase mala: la F-RAM recibe 06 = WREN
    PAD  7
    sb   a2, 3(s7)            # escribe el caracter en 4 bytes
    PAD  7
    lhu  t1, 0(s7)            # relee dos de esos bytes
    beq  t1, a3, guardado_cal     # coincide: quedo guardado
    addi a5, a4, -1
    addi a4, a5, 0
    beqz a4, guardado_cal         # se acabaron los intentos
    PAD  1                    # correr la fase un paso y repetir
    j    guardar_cal
    nop
guardado_cal:
    li   a7,  13        # '\r'
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    li   a7,  10        # '\n'
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    li   a7,  62        # '>'
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    li   a7,  32        # ' '
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    addi s7, s4, 0            # s7 = donde va el siguiente caracter

# ---- recibir y mostrar ----
    nop
leer:
    lw   t0, 0(s1)
    andi t1, t0, 0x100        # llego un dato?
    beqz t1, leer
    lw   a1, 0(s0)            # leer el caracter
    li   t0, 1
    sw   t0, 0(s1)            # avisar que ya se atendio
    sw   zero, 0(s1)
    andi a2, a1, 0xFF         # a2 = caracter
    li   t0, 13
    beq  a2, t0, responder    # Enter (CR)
    li   t0, 10
    beq  a2, t0, responder    # Enter (LF)
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a2, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    add  t1, a2, a2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1           # t2 = 256 * caracter
    add  a3, t2, a2         # a3 = caracter repetido en dos bytes
    li   a4, INTENTOS
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # esperar a que la UART termine de enviar
    bnez t5, 1b
    PAD  6

# ---- guardar en la RAM y comprobar ----
    nop
guardar:
    lw   t0, 0(s7)            # A PROPOSITO en fase mala: la F-RAM recibe 06 = WREN
    PAD  7
    sb   a2, 3(s7)            # escribe el caracter en 4 bytes
    PAD  7
    lhu  t1, 0(s7)            # relee dos de esos bytes
    beq  t1, a3, guardado     # coincide: quedo guardado
    addi a5, a4, -1
    addi a4, a5, 0
    beqz a4, guardado         # se acabaron los intentos
    PAD  1                    # correr la fase un paso y repetir
    j    guardar
    nop
guardado:
    add  t0, s7, s8
    addi s7, t0, 0
    bne  s7, s9, leer

# ---- leer de la RAM y devolver en mayusculas ----
    nop
responder:
    li   a7,  13        # '\r'
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    li   a7,  10        # '\n'
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    beq  s7, s4, nueva        # linea vacia
    addi s10, s4, 0
    PAD  0
    nop
sacar:
    li   a4, INTENTOS
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # esperar a que la UART termine de enviar
    bnez t5, 1b
    nop
sacar2:
    PAD  7
    lhu  a0, 0(s10)          # dos bytes del caracter
    andi a2, a0, 0xFF
    add  t1, a2, a2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1           # t2 = 256 * caracter
    add  a3, t2, a2         # a3 = caracter repetido en dos bytes
    bne  a0, a3, mal         # los dos bytes deben ser iguales
    beqz a2, mal              # 00: la RAM no respondio
    li   t0, 255
    beq  a2, t0, mal          # FF: la RAM no respondio
    j    bien
    nop
mal:
    addi a5, a4, -1
    addi a4, a5, 0
    beqz a4, rendirse
    PAD  1                    # correr la fase un paso y repetir
    j    sacar2
    nop
rendirse:
    li   a2, 63               # '?': no se pudo leer
    nop
bien:
    li   t0, 97
    blt  a2, t0, listo        # menor que 'a': se deja igual
    li   t0, 123
    bge  a2, t0, listo        # mayor que 'z': se deja igual
    addi a6, a2, -32          # minuscula -> mayuscula
    addi a2, a6, 0
    nop
listo:
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a2, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    add  t0, s10, s8
    addi s10, t0, 0
    bne  s10, s7, sacar
    PAD  0
    j    nueva

    .word 0
