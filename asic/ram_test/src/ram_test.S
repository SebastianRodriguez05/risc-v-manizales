# ram_test.S - Prueba de la RAM SPI (F-RAM FM25V02) desde el femto_UN (tt_um_femto)
#
# Imprime por la UART:
#   L1, L2 : lee dos posiciones de la RAM (lo que haya dejado grabado el ESP32)
#   E1     : lee un contador, le suma 1, lo escribe (con el truco del WREN) y lo relee
#   E2     : lo mismo en otra posicion pero SIN el truco del WREN (prueba de control)
#
# Mapa: 0x00400008 dato UART, 0x00400010 control/estado UART, 0x0001xxxx RAM SPI.
#
# OJO - los bloques PAD no son relleno casual. El reloj SPI de la RAM (clk/11) nunca se
# detiene y CS baja cuando el procesador lo pide. Si CS baja con ese reloj en alto, el primer
# bit del comando se pierde: la RAM ve 06 en vez de 03 y 04 en vez de 02. Una instruccion
# normal dura 198 ciclos (multiplo de 11), asi que por si sola nunca cambia esa fase. Cada
# 'slli zero,zero,2' dura 201 y la adelanta 3 pasos. Los valores de PAD salieron de la
# simulacion ciclo a ciclo del chip: todos los accesos caen en fase 0 (CS baja 5 ciclos antes
# del flanco de subida) menos el que hace de WREN, que cae en fase 8 a proposito.
# Las instrucciones normales y la UART no mueven la fase; solo la mueven los accesos a la
# RAM y los corrimientos. Si se cambia la cantidad o el orden de los accesos a la RAM, hay
# que recalcular los PAD.
#
# El programa tarda siempre lo mismo sin importar los datos leidos (puthex no tiene saltos
# que dependan del valor). No usa x31/t6: un fetch fallido se ejecuta como 'jal x31,-2'.

.macro PAD n
    .rept \n
    slli zero, zero, 2
    .endr
.endm

    .section .text
    .globl _start
_start:
    lui  s0, 0x400            # s0 = 0x00400000
    addi s1, s0, 0x10         # s1 = control/estado de la UART
    addi s0, s0, 0x08         # s0 = dato de la UART
    lui  s4, 0x10             # s4 = 0x00010000, base de la RAM
    lui  s5, 0x80000
    addi s5, s5, -1           # s5 = 0x7FFFFFFF (el bit 31 leido de la RAM no es valido)
    lui  t0, 0x1
    add  s7, s4, t0           # s7 = RAM + 0x1000
    add  s8, s7, t0           # s8 = RAM + 0x2000
    add  s9, s8, t0           # s9 = RAM + 0x3000

    li   a1,  13        # '\r'
    jal  ra, putc
    li   a1,  10        # '\n'
    jal  ra, putc
    li   a1,  82        # 'R'
    jal  ra, putc
    li   a1,  65        # 'A'
    jal  ra, putc
    li   a1,  77        # 'M'
    jal  ra, putc
    li   a1,  32        # ' '
    jal  ra, putc
    li   a1, 102        # 'f'
    jal  ra, putc
    li   a1, 101        # 'e'
    jal  ra, putc
    li   a1, 109        # 'm'
    jal  ra, putc
    li   a1, 116        # 't'
    jal  ra, putc
    li   a1, 111        # 'o'
    jal  ra, putc
    li   a1,  95        # '_'
    jal  ra, putc
    li   a1,  85        # 'U'
    jal  ra, putc
    li   a1,  78        # 'N'
    jal  ra, putc
    li   a1,  13        # '\r'
    jal  ra, putc
    li   a1,  10        # '\n'
    jal  ra, putc

# ---- L1: lectura de RAM+0x0000 ----
    li   a1,  76        # 'L'
    jal  ra, putc
    li   a1,  49        # '1'
    jal  ra, putc
    li   a1,  32        # ' '
    jal  ra, putc
    PAD  5
    lw   a0, 0(s4)
    and  a0, a0, s5
    jal  ra, puthex
    li   a1,  13        # '\r'
    jal  ra, putc
    li   a1,  10        # '\n'
    jal  ra, putc

# ---- L2: lectura de RAM+0x1000 ----
    li   a1,  76        # 'L'
    jal  ra, putc
    li   a1,  50        # '2'
    jal  ra, putc
    li   a1,  32        # ' '
    jal  ra, putc
    PAD  7
    lw   a0, 0(s7)
    and  a0, a0, s5
    jal  ra, puthex
    li   a1,  13        # '\r'
    jal  ra, putc
    li   a1,  10        # '\n'
    jal  ra, putc

# ---- E1: contador en RAM+0x2000, escritura con WREN ----
    li   a1,  69        # 'E'
    jal  ra, putc
    li   a1,  49        # '1'
    jal  ra, putc
    li   a1,  32        # ' '
    jal  ra, putc
    PAD  7
    lw   a0, 0(s8)            # valor anterior
    and  a0, a0, s5
    addi s6, a0, 1            # s6 = anterior + 1
    jal  ra, puthex
    li   a1,  32        # ' '
    jal  ra, putc
    PAD  6
    lw   t0, 0(s8)            # A PROPOSITO en fase mala: la F-RAM recibe 06 = WREN
    PAD  7
    sw   s6, 0(s8)            # escritura
    PAD  7
    lw   a0, 0(s8)            # relectura
    and  a0, a0, s5
    jal  ra, puthex
    li   a1,  13        # '\r'
    jal  ra, putc
    li   a1,  10        # '\n'
    jal  ra, putc

# ---- E2: contador en RAM+0x3000, escritura SIN WREN (control) ----
    li   a1,  69        # 'E'
    jal  ra, putc
    li   a1,  50        # '2'
    jal  ra, putc
    li   a1,  32        # ' '
    jal  ra, putc
    PAD  7
    lw   a0, 0(s9)
    and  a0, a0, s5
    addi s6, a0, 1
    jal  ra, puthex
    li   a1,  32        # ' '
    jal  ra, putc
    PAD  3
    sw   s6, 0(s9)
    PAD  7
    lw   a0, 0(s9)
    and  a0, a0, s5
    jal  ra, puthex
    li   a1,  13        # '\r'
    jal  ra, putc
    li   a1,  10        # '\n'
    jal  ra, putc
    li   a1,  70        # 'F'
    jal  ra, putc
    li   a1,  73        # 'I'
    jal  ra, putc
    li   a1,  78        # 'N'
    jal  ra, putc
    li   a1,  13        # '\r'
    jal  ra, putc
    li   a1,  10        # '\n'
    jal  ra, putc

    li   t0, 4
    sw   t0, 0(s1)            # enciende el LED de uo[6]
fin:
    j    fin

# ---- putc: envia a1 por la UART ----
putc:
    lw   t4, 0(s1)
    andi t4, t4, 0x200        # bit 9 = transmisor ocupado
    bnez t4, putc
    sw   a1, 0(s0)
    li   t4, 8
    sw   t4, 0(s1)            # pulso de tx_wr
    sw   zero, 0(s1)
    ret

# ---- puthex: imprime a0 en 8 digitos hexadecimales ----
# Sin saltos que dependan del dato: siempre tarda lo mismo, para no mover las fases.
puthex:
    mv   s2, ra
    li   s3, 8
1:  li   t0, 0
    .rept 4
    slt  t1, a0, zero         # t1 = bit 31
    add  t0, t0, t0
    add  t0, t0, t1
    add  a0, a0, a0
    .endr
    sltiu t1, t0, 10
    xori t1, t1, 1            # t1 = 1 si el digito es A..F
    add  t2, t1, t1
    add  t2, t2, t1
    add  t2, t2, t2
    add  t2, t2, t1           # t2 = 7 * t1
    addi t0, t0, 48
    add  a1, t0, t2
    jal  ra, putc
    addi s3, s3, -1
    bnez s3, 1b
    jr   s2

    .word 0
