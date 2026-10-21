# =============================================================================
# mayus3.S - Eco en mayusculas a traves de la RAM SPI   (femto_UN / tt_um_femto)
#            Version 3.0: lineas de hasta 126 caracteres (antes 50)
# =============================================================================
#
# ESTADO: SIN PROBAR EN HARDWARE. La version en uso sigue siendo mayus2.S.
#
# CAMBIOS RESPECTO A mayus2.S
#   - La separacion entre caracteres en la RAM pasa de 0x500 a 0x200, y el
#     maximo por linea de 50 a 126 caracteres (ver "ORGANIZACION DE LA RAM").
#   - La separacion y el maximo son constantes (SEPARACION, MAX_CHARS) y el
#     limite de la linea se calcula a partir de ellas.
#   - Nada mas cambia: misma cantidad y mismo orden de instrucciones que
#     mayus2.S, asi que todos los PAD (fases de la RAM) siguen valiendo.
#     Solo cambia el inmediato de dos instrucciones de _start.
#
# QUE HACE
#   1. Muestra el indicador "> ".
#   2. Cada caracter que llega por la UART se devuelve (eco) y se guarda en la
#      RAM SPI externa (F-RAM FM25V02).
#   3. Al recibir Enter (CR o LF), o al completar MAX_CHARS (126) caracteres, lee la linea
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
#     s8  = SEPARACION   separacion entre caracteres en la RAM (0x200)
#     s9  = s4 + MAX_CHARS*SEPARACION  fin de linea (tambien calibracion)
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
#   El controlador SPI solo usa los bits 15..8 de la direccion: el byte de
#   la F-RAM que se accede es (direccion >> 8) & 0xFF, es decir, solo hay
#   256 posiciones utiles. Una separacion de 0x200 son 2 bytes de la F-RAM.
#
#   Cada escritura graba el caracter en 4 bytes seguidos (b, b+1, b+2, b+3),
#   pero al leer solo se usan los dos primeros ('lhu' -> b y b+1). Por eso
#   los caracteres se pueden solapar: el caracter i+1 escribe encima de los
#   bytes b+2 y b+3 del caracter i, que ya no se necesitan.
#
#       byte F-RAM:   0   1   2   3   4   5   6   7  ...
#       caracter 0:  [c0  c0] c0  c0
#       caracter 1:          [c1  c1] c1  c1
#       caracter 2:                  [c2  c2] c2  c2
#                    [..] = bytes que se releen y comparan
#
#   El caracter numero i va en  RAM + i*SEPARACION  (i = 0..MAX_CHARS-1),
#   y la posicion MAX_CHARS se usa solo para la letra de calibracion 'Z'.
#   La calibracion escribe hasta el byte 2*126+3 = 255, el ultimo que hay.
#
#   Configuraciones validas (SEPARACION -> MAX_CHARS):
#       0x500 -> 50    igual que mayus2.S (sin solape, probada)
#       0x400 -> 63    sin solape, opcion intermedia si 0x200 falla
#       0x200 -> 126   con solape (por defecto en esta version)
#   Regla general: (SEPARACION>>8)*MAX_CHARS + 3 <= 255.
#   Si el solape da problemas en hardware, probar primero con 0x400.
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
#      - Al empezar cada linea se guarda una letra de prueba en la posicion MAX_CHARS
#        para dejar la fase ajustada antes de mostrar el indicador.
#    Hay INTENTOS reintentos por operacion; si se agotan se sigue adelante
#    (al guardar) o se envia '?' (al leer).
#
# =============================================================================

.equ INTENTOS, 24             # reintentos por cada escritura o lectura de RAM
.equ SEPARACION, 0x200        # distancia entre caracteres (debe caber en 12 bits)
.equ MAX_CHARS, 126           # caracteres por linea (ver ORGANIZACION DE LA RAM)
.equ LIMITE, MAX_CHARS*SEPARACION   # 126*0x200 = 0xFC00

.if (SEPARACION >> 8) * MAX_CHARS + 3 > 255
.error "MAX_CHARS no cabe en la RAM con esta SEPARACION"
.endif

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
    addi s8, zero, SEPARACION # s8 = separacion entre caracteres
    # t1 = LIMITE con lui+addi en registros distintos (no 'li t1', que usaria
    # t1 como origen y destino, ver restriccion 1). Mismo numero de
    # instrucciones que en mayus2.S, para no mover las fases.
    lui  t0, %hi(LIMITE)
    addi t1, t0, %lo(LIMITE)  # t1 = MAX_CHARS*SEPARACION
    add  s9, s4, t1           # s9 = RAM + LIMITE (limite de la linea)
    PAD  9                    # alinear la fase SPI para la primera calibracion

# =============================================================================
# Nueva linea: calibrar la RAM y mostrar el indicador "> "
# =============================================================================
    nop
nueva:
# ---- calibracion: guardar y comprobar 'Z' en la posicion MAX_CHARS ----
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
    add  t0, s7, s8           # s7 = s7 + SEPARACION (en dos pasos)
    addi s7, t0, 0
    bne  s7, s9, leer         # quedan posiciones: seguir recibiendo
                              # MAX_CHARS caracteres: responder sin esperar Enter

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
    add  t0, s10, s8          # s10 = s10 + SEPARACION (en dos pasos)
    addi s10, t0, 0
    bne  s10, s7, sacar       # faltan caracteres de la linea
    PAD  0
    j    nueva                # linea terminada: empezar otra

    .word 0                   # relleno al final de la imagen
