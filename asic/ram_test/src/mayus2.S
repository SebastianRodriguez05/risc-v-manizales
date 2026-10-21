# =============================================================================
# mayus2.S - Eco en mayusculas a traves de la RAM SPI   (femto_UN / tt_um_femto)
# =============================================================================
#
# QUE HACE
#   1. Muestra el indicador "> ".
#   2. Cada caracter que llega por la UART se devuelve (eco) y se guarda en la
#      RAM SPI externa (F-RAM FM25V02).
#   3. Al recibir Enter (CR o LF), o al completar 50 caracteres, lee la linea
#      desde la RAM y la envia convertida: a..z -> A..Z, lo demas sin cambios.
#   4. Si un caracter no se pudo leer de la RAM, en su lugar se envia '?'.
#
#   Ejemplo:   > hola mundo 123
#              HOLA MUNDO 123
#
# El programa tolera los fallos conocidos de la flash y de la RAM SPI y se
# recalibra solo (ver "RESTRICCIONES DE DISENO").
#
# -----------------------------------------------------------------------------
# MAPA DE MEMORIA
# -----------------------------------------------------------------------------
#   0x00400008  UART dato     (lectura: byte recibido / escritura: byte a enviar)
#   0x00400010  UART control/estado
#                 lectura:   bit 9 = transmisor ocupado
#                            bit 8 = hay un dato recibido
#                 escritura: 8 = enviar el dato cargado
#                            1 = marcar el dato recibido como atendido
#                            (despues de cada pulso se escribe 0)
#   0x0001xxxx  RAM SPI (F-RAM FM25V02)
#
# -----------------------------------------------------------------------------
# USO DE REGISTROS
# -----------------------------------------------------------------------------
#   Fijos (se cargan una vez en _start):
#     s0  = 0x00400008   dato de la UART
#     s1  = 0x00400010   control/estado de la UART
#     s4  = 0x00010000   base de la RAM (posicion del caracter 0)
#     s8  = 0x500        separacion entre caracteres en la RAM
#     s9  = s4 + 50*0x500  fin de linea (tambien posicion de calibracion)
#   De trabajo:
#     s7  = posicion donde se guarda el siguiente caracter
#     s10 = posicion del caracter que se esta leyendo
#     a2  = caracter actual
#     a3  = caracter repetido en dos bytes (a2*257), valor esperado al releer
#     a4  = intentos restantes (a5 es su temporal)
#     a6  = temporal de la conversion a mayuscula
#     a7  = caracter fijo a enviar (CR, LF, '>', ' ')
#     t0..t5 = temporales
#   Prohibido: x31 (t6), ver restriccion 1.
#
# -----------------------------------------------------------------------------
# ORGANIZACION DE LA RAM
# -----------------------------------------------------------------------------
#   El caracter numero i se guarda en  RAM + i*0x500  (i = 0..49).
#   La posicion 50 (= s9) se usa solo para la letra de calibracion 'Z'.
#   El controlador SPI solo usa los bits 15..8 de la direccion, por eso 0x500
#   equivale a 5 bytes reales de la F-RAM entre un caracter y el siguiente.
#   Cada caracter se escribe repetido en 4 bytes ('sb' con desplazamiento 3);
#   al leer se toman dos de ellos con 'lhu' y deben coincidir.
#
# -----------------------------------------------------------------------------
# RESTRICCIONES DE DISENO (por que el codigo se ve "raro")
# -----------------------------------------------------------------------------
#
# 1) Fetch fallido de la flash.
#    A veces la flash no atiende una lectura de instruccion y el femto recibe
#    0xFFFFFFFF, que ejecuta como 'jal x31,-2'. El efecto alterna: unas veces
#    solo reintenta, y otras ejecuta ademas la instruccion inmediatamente
#    ANTERIOR. Para que una instruccion repetida no cause dano:
#      - Ninguna instruccion escribe un registro que tambien lee. Por eso, en
#        vez de 'addi a4,a4,-1' se usa 'addi a5,a4,-1' + 'addi a4,a5,0'
#        (repetir cualquiera de las dos da el mismo resultado).
#      - Antes de cada etiqueta hay un 'nop': si al saltar se cuela la
#        instruccion anterior, es ese nop.
#      - No hay subrutinas: repetir un 'jal' repetiria la llamada completa.
#        Por eso el envio por UART esta copiado en linea cada vez.
#      - No se usa x31 (t6), porque el 'jal' fantasma lo sobrescribe.
#
# 2) Fase del reloj SPI.
#    El reloj de la RAM (clk/11) corre siempre. Si CS baja mientras ese reloj
#    esta en alto se pierde el primer bit del comando:
#        READ  (03) llega como 06 (WREN)
#        WRITE (02) llega como 04
#    Una instruccion normal dura 198 ciclos; PAD ('slli zero,zero,2') dura 201,
#    asi que cada PAD adelanta la fase 3 pasos (de 11). Los PAD estan
#    colocados para que:
#        - el 'lw' de "habilitar escritura" caiga en la fase 8 (fase MALA a
#          proposito: su 03 llega como 06 = WREN, que habilita la escritura);
#        - el 'sb' y el 'lhu' caigan en la fase 0 (fase buena).
#    'PAD 0' no genera nada; marca un punto donde se puede ajustar la fase.
#
# 3) Autocalibracion.
#    Una instruccion repetida (restriccion 1) corre la fase y desalinearia todo
#    lo que sigue. Por eso nada se da por hecho:
#      - Al guardar: se escribe, se relee y se compara. Si no coincide se
#        agrega un PAD (corre la fase un paso) y se repite.
#      - Al leer: los dos bytes deben ser iguales y distintos de 00 y FF
#        (00/FF = la RAM no respondio). Si no, se agrega un PAD y se repite.
#      - Al empezar cada linea se guarda una letra de prueba en la posicion 50
#        para dejar la fase ajustada antes de mostrar el indicador.
#    Hay INTENTOS reintentos por operacion; si se agotan se sigue adelante
#    (al guardar) o se envia '?' (al leer).
#
# =============================================================================

.equ INTENTOS, 24             # reintentos por cada escritura o lectura de RAM

# PAD n: n instrucciones de 201 ciclos; cada una adelanta 3 pasos la fase SPI
.macro PAD n
    .rept \n
    slli zero, zero, 2
    .endr
.endm

    .section .text
    .globl _start

# =============================================================================
# Inicio: cargar direcciones fijas
# =============================================================================
_start:
    lui  t0, 0x400
    addi s1, t0, 0x10         # s1 = control/estado de la UART
    addi s0, t0, 0x08         # s0 = dato de la UART
    lui  s4, 0x10             # s4 = 0x00010000, base de la RAM
    addi s8, zero, 0x500      # s8 = separacion entre caracteres
    lui  t0, 0x10
    addi t1, t0, -0x600       # t1 = 0x10000 - 0x600 = 0xFA00 = 50*0x500
    add  s9, s4, t1           # s9 = RAM + 50*0x500 (limite de la linea)
    PAD  9                    # alinear la fase SPI para la primera calibracion

# =============================================================================
# Nueva linea: calibrar la RAM y mostrar el indicador "> "
# =============================================================================
    nop
nueva:
# ---- calibracion: guardar y comprobar 'Z' en la posicion 50 ----
    addi s7, s9, 0            # s7 = posicion de calibracion
    li   a2, 0x5A             # letra de prueba 'Z'
    # a3 = a2 * 257 (el caracter en los dos bytes que se releen).
    # Se multiplica por 256 duplicando 8 veces, alternando t1/t2 para que
    # ninguna instruccion lea y escriba el mismo registro.
    add  t1, a2, a2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1           # t2 = 256 * caracter
    add  a3, t2, a2           # a3 = caracter repetido en dos bytes
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
    beq  t1, a3, guardado_cal # coincide: la fase esta bien
    addi a5, a4, -1           # a4 = a4 - 1 (en dos pasos, ver restriccion 1)
    addi a4, a5, 0
    beqz a4, guardado_cal     # se acabaron los intentos
    PAD  1                    # correr la fase un paso y repetir
    j    guardar_cal
    nop
guardado_cal:

# ---- enviar "\r\n> " ----
    li   a7,  13              # '\r'
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    li   a7,  10              # '\n'
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    li   a7,  62              # '>'
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    li   a7,  32              # ' '
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    addi s7, s4, 0            # s7 = posicion del caracter 0

# =============================================================================
# Recibir un caracter y hacer eco
# =============================================================================
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
    sw   a2, 0(s0)            # eco
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    # a3 = a2 * 257 (ver calibracion)
    add  t1, a2, a2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1           # t2 = 256 * caracter
    add  a3, t2, a2           # a3 = caracter repetido en dos bytes
    li   a4, INTENTOS
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # esperar a que el eco termine de salir
    bnez t5, 1b
    PAD  6

# =============================================================================
# Guardar el caracter en la RAM y comprobarlo
# =============================================================================
    nop
guardar:
    lw   t0, 0(s7)            # A PROPOSITO en fase mala: la F-RAM recibe 06 = WREN
    PAD  7
    sb   a2, 3(s7)            # escribe el caracter en 4 bytes
    PAD  7
    lhu  t1, 0(s7)            # relee dos de esos bytes
    beq  t1, a3, guardado     # coincide: quedo guardado
    addi a5, a4, -1           # a4 = a4 - 1 (en dos pasos, ver restriccion 1)
    addi a4, a5, 0
    beqz a4, guardado         # se acabaron los intentos
    PAD  1                    # correr la fase un paso y repetir
    j    guardar
    nop
guardado:
    add  t0, s7, s8           # s7 = s7 + 0x500 (en dos pasos)
    addi s7, t0, 0
    bne  s7, s9, leer         # quedan posiciones: seguir recibiendo
                              # 50 caracteres: responder sin esperar Enter

# =============================================================================
# Responder: leer la linea de la RAM y enviarla en mayusculas
# =============================================================================
    nop
responder:
    li   a7,  13              # '\r'
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    li   a7,  10              # '\n'
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # transmisor ocupado?
    bnez t5, 1b
    sw   a7, 0(s0)
    li   t3, 8
    sw   t3, 0(s1)            # pulso de envio
    sw   zero, 0(s1)
    beq  s7, s4, nueva        # linea vacia: no hay nada que devolver
    addi s10, s4, 0           # s10 = posicion del caracter 0
    PAD  0
    nop

# ---- por cada caracter guardado ----
sacar:
    li   a4, INTENTOS
    nop
1:  lw   t4, 0(s1)
    andi t5, t4, 0x200        # esperar a que la UART termine de enviar
    bnez t5, 1b
    nop
sacar2:
    PAD  7
    lhu  a0, 0(s10)           # dos bytes del caracter
    andi a2, a0, 0xFF         # a2 = caracter leido
    # a3 = a2 * 257: lo que deberia valer a0 si ambos bytes coinciden
    add  t1, a2, a2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1
    add  t1, t2, t2
    add  t2, t1, t1           # t2 = 256 * caracter
    add  a3, t2, a2           # a3 = caracter repetido en dos bytes
    bne  a0, a3, mal          # los dos bytes deben ser iguales
    beqz a2, mal              # 00: la RAM no respondio
    li   t0, 255
    beq  a2, t0, mal          # FF: la RAM no respondio
    j    bien
    nop
mal:
    addi a5, a4, -1           # a4 = a4 - 1 (en dos pasos, ver restriccion 1)
    addi a4, a5, 0
    beqz a4, rendirse
    PAD  1                    # correr la fase un paso y repetir
    j    sacar2
    nop
rendirse:
    li   a2, 63               # '?': no se pudo leer
    nop

# ---- convertir a mayuscula y enviar ----
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
    add  t0, s10, s8          # s10 = s10 + 0x500 (en dos pasos)
    addi s10, t0, 0
    bne  s10, s7, sacar       # faltan caracteres de la linea
    PAD  0
    j    nueva                # linea terminada: empezar otra

    .word 0                   # relleno al final de la imagen
