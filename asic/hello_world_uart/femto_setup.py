# Configura la demo board de Tiny Tapeout para correr tt_um_femto con memorias externas.
# Uso desde el REPL (mpremote):
#     FREQ=100000; exec(open('femto_setup.py').read())
#     tt.reset_project(False)
# Deja el proyecto EN RESET para poder armar el analizador antes de soltarlo.
from ttboard.demoboard import DemoBoard
from ttboard.mode import RPMode
from machine import Pin

FREQ = globals().get('FREQ', 500000)

tt = DemoBoard.get()
tt.clock_project_stop()
tt.mode = RPMode.ASIC_RP_CONTROL
tt.shuttle.tt_um_femto.enable()
print(tt.shuttle.enabled)

# Liberar los pines que manejan la flash, la RAM y la UART.
# OJO: .mode = Pin.IN es lo que realmente los pasa a entrada; con .init(Pin.IN)
# el RP2350 seguia manejando ui_in0 como salida en 0 y la flash no podia responder.
for nombre in ("ui_in0", "ui_in1", "ui_in2",
               "uo_out2", "uo_out3", "uo_out4", "uo_out5"):
    p = getattr(tt.pins, nombre)
    p.mode = Pin.IN
    print(p)

tt.reset_project(True)
tt.clock_project_PWM(FREQ)
print("reloj:", tt.auto_clocking_freq, "- proyecto EN RESET")
