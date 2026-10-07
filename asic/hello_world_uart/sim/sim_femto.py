#!/usr/bin/env python3
"""
Modelo ciclo a ciclo del femto_UN (tt_um_femto) tal como se fabrico:
commit baab83f de github.com/cicamargoba/femto_UN (MappedSPIFlash.v,
femtorv32_quark.v, uart.v, perip_uart.v), ejecutando el firmware real.

Es un modelo en Python escrito a partir del RTL, no una simulacion del Verilog.
Sirve para ver que pide el femto por SPI en cada fase y que sale por la UART
segun como se comporte la memoria flash.

Uso:
    python3 sim_femto.py firmware.bin      # el .bin SIN corrimiento (no el _shifted)

Comportamientos de flash que compara:
    tolerante : contesta tambien las lecturas con el primer bit perdido (0x06)
    real      : solo contesta 0x03 y alcanza a ver el flanco simultaneo CS/CLK
    sin_flanco: solo contesta 0x03 y NO ve el flanco simultaneo CS/CLK
"""
import sys, random
M32=0xFFFFFFFF
def sx(v,b): return v-(1<<b) if v>>(b-1)&1 else v
def shift_right1(data):
    bits=''.join(f'{b:08b}' for b in data); bits='0'+bits[:-1]
    return bytes(int(bits[i:i+8],2) for i in range(0,len(bits),8))
FW=open(sys.argv[1] if len(sys.argv)>1 else 'firmware.bin','rb').read()

def run(ncyc, flashmode='esp', image=None, rf_init=None, idle=1, reset_len=20, trace=0, skip_first=False):
    mem = image if image is not None else shift_right1(FW)
    def fbit(addr,i):
        a=(addr+i//8)&0x7FFFFF
        byte=mem[a] if a<len(mem) else 0xFF
        return (byte>>(7-i%8))&1
    RF=list(rf_init) if rf_init else [0]*32
    RF[0]=0
    # flash controller
    START,WAIT_STRB,SEND,RECEIVE=range(4)
    st=START; rbusy=0; CS=1; cmd=0; snd=0; rcv=0; rdat=0; d=0; clk_div=0; CLK=0
    resetn=0
    # cpu
    FETCH,WAITI,EXEC,WAITM=range(4)
    cst=WAITM; PC=0; instr=0; rs1=0; rs2=0; wmask=0; aluShamt=0
    # uart
    en16=12; d_in_uart=0; ctrl=0; led=0; tx_busy=0; txd=1; tx_cnt16=0; tx_bit=0; txd_reg=0
    # device
    dev=dict(bits=[],out=None,addr=0,active=False,mode=None)
    miso=idle
    sent=[]; trans=[]; curtx=None
    for n in range(ncyc):
        rst_n = 0 if n<reset_len else 1
        # ---------- combinational (values before negedge)
        def decode():
            op=(instr>>2)&31; f3=(instr>>12)&7
            isLoad=op==0; isALUimm=op==4; isStore=op==8; isALUreg=op==12; isSYSTEM=op==28
            isJAL=(instr>>3)&1; isJALR=op==25; isLUI=op==13; isAUIPC=op==5; isBranch=op==24
            isALU=isALUimm or isALUreg
            Iimm=sx(instr>>20,12)&M32
            Simm=sx(((instr>>25)<<5)|((instr>>7)&31),12)&M32
            Bimm=sx(((instr>>31)<<12)|(((instr>>7)&1)<<11)|(((instr>>25)&63)<<5)|(((instr>>8)&15)<<1),13)&M32
            Jimm=sx(((instr>>31)<<20)|(((instr>>12)&255)<<12)|(((instr>>20)&1)<<11)|(((instr>>21)&1023)<<1),21)&M32
            Uimm=instr&0xFFFFF000
            a1=rs1; a2=rs2 if (isALUreg or isBranch) else Iimm
            plus=(a1+a2)&M32; minus=(a1-a2)&M32; EQ=minus==0
            LT=(sx(a1,32)<sx(a2,32)); LTU=a1<a2
            if f3==0: alu= minus if ((instr>>30)&1 and (instr>>5)&1) else plus
            elif f3==2: alu=int(LT)
            elif f3==3: alu=int(LTU)
            elif f3==4: alu=a1^a2
            elif f3==6: alu=a1|a2
            elif f3==7: alu=a1&a2
            else: alu=0
            pred={0:EQ,1:not EQ,4:LT,5:not LT,6:LTU,7:not LTU}.get(f3,False)
            PCimm=(PC+(Jimm if (instr>>3)&1 else Uimm if (instr>>4)&1 else Bimm))&M32
            ls=(rs1+(Simm if (instr>>5)&1 else Iimm))&M32
            return locals()
        D=decode()
        mem_addr = PC if cst in (FETCH,WAITI) else D['ls']
        if not resetn: mem_addr=0
        hi=mem_addr>>16
        csel = 'uart' if hi==0x40 else 'ram' if hi==1 else 'flash'
        rstrb = resetn and (cst==FETCH or (cst==EXEC and D['isLoad']))
        frstrb = rstrb and csel=='flash'
        flash_rdata=int.from_bytes(rdat.to_bytes(4,'big'),'little')
        uaddr=mem_addr&31
        s0 = csel=='uart' and uaddr==8; s1= csel=='uart' and uaddr==0x10
        uart_dout = (0) if s0 else ((tx_busy<<9) if s1 else 0)
        mem_rdata = uart_dout if csel=='uart' else 0 if csel=='ram' else flash_rdata
        writeBack = resetn and cst in (EXEC,WAITM) and not (D['isBranch'] or D['isStore'])
        f3=(instr>>12)&7
        if f3&3==0:
            hw=(mem_rdata>>16)&0xFFFF if D['ls']&2 else mem_rdata&0xFFFF
            by=(hw>>8)&255 if D['ls']&1 else hw&255
            LOAD=(sx(by,8)&M32) if not (instr>>14)&1 else by
        elif f3&3==1:
            hw=(mem_rdata>>16)&0xFFFF if D['ls']&2 else mem_rdata&0xFFFF
            LOAD=(sx(hw,16)&M32) if not (instr>>14)&1 else hw
        else: LOAD=mem_rdata
        wbd=0
        if D['isLUI']: wbd|=D['Uimm']
        if D['isALU']: wbd|=D['alu']
        if D['isAUIPC']: wbd|=D['PCimm']
        if D['isJALR'] or D['isJAL']: wbd|=(PC+4)&M32
        if D['isLoad']: wbd|=LOAD
        rd=(instr>>7)&31
        # ---------- negedge
        n_resetn=rst_n
        nCLK=CLK; nclk_div=clk_div; nd=d
        nst,nCS,ncmd,nsnd,nrcv,nrdat,nrbusy=st,CS,cmd,snd,rcv,rdat,rbusy
        if not resetn:
            nclk_div=0; nd=0; nCLK=0; nst=START; nrbusy=0; nrdat=0; nCS=1; ncmd=0
        else:
            if d>=2: nclk_div=1; nd=0
            else: nclk_div=0; nd=d+1
            if d==1 or d==2: nCLK=1-CLK
            if st==START: nCS=1; nrbusy=0; nsnd=0; nrcv=0; nst=WAIT_STRB
            elif st==WAIT_STRB:
                if frstrb:
                    nCS=0; nrbusy=1; nsnd=32
                    wa=(mem_addr>>2)&0xFFFFF
                    ncmd=(0x03<<24)|(wa<<2); nst=SEND
                    curtx=dict(n=n,d=d,kind='F' if cst==FETCH else 'L',addr=wa<<2)
            elif st==SEND:
                if clk_div:
                    if snd==1: nrcv=32; nst=RECEIVE
                    else: nsnd=snd-1; ncmd=((cmd<<1)|1)&M32
            elif st==RECEIVE:
                if clk_div:
                    if rcv==0: nst=START
                    else: nrcv=rcv-1; nrdat=((rdat<<1)|miso)&M32
        # regfile
        if writeBack and rd!=0: RF[rd]=wbd
        RF[0]=0
        # device sees pin changes
        mosi_before=(cmd>>31)&1
        if CS==1 and nCS==0:
            dev.update(bits=[],out=None,active=True,mode=None)
            if nCLK==1 and CLK==0 and flashmode in('esp','catch'): dev['bits'].append((ncmd>>31)&1)
        elif CS==0 and nCS==0 and dev['active']:
            if CLK==0 and nCLK==1 and dev['out'] is None:
                dev['bits'].append(mosi_before); nb=len(dev['bits'])
                if nb==8:
                    c=int(''.join(map(str,dev['bits'])),2); dev['cmd']=c
                    if c==3: dev['mode']=24
                    elif c in(6,7) and flashmode=='esp': dev['mode']=23
                    else: dev['mode']=None
                if dev['mode'] and nb==8+dev['mode']:
                    ab=dev['bits'][8:]
                    a=int(''.join(map(str,ab)),2)
                    if dev['mode']==23: a|=(dev['cmd']&1)<<23
                    dev['addr']=a&0xFFFFFF; dev['out']=0
                    if skip_first: pass
            if CLK==1 and nCLK==0 and dev['out'] is not None:
                miso=fbit(dev['addr'],dev['out']); dev['out']+=1
        if CS==0 and nCS==1:
            dev['active']=False; miso=idle
            if curtx is not None:
                curtx['cmd']=dev.get('cmd'); curtx['word']=int.from_bytes(nrdat.to_bytes(4,'big'),'little')
                trans.append(curtx); curtx=None
        st,CS,cmd,snd,rcv,rdat,rbusy,CLK,clk_div,d=nst,nCS,ncmd,nsnd,nrcv,nrdat,nrbusy,nCLK,nclk_div,nd
        old_resetn=resetn; resetn=n_resetn
        # ---------- posedge (cpu uses resetn after negedge update; comb signals re-evaluated)
        D=decode()
        mem_addr = (PC if cst in (FETCH,WAITI) else D['ls']) if resetn else 0
        hi=mem_addr>>16
        csel = 'uart' if hi==0x40 else 'ram' if hi==1 else 'flash'
        flash_rdata=int.from_bytes(rdat.to_bytes(4,'big'),'little')
        uaddr=mem_addr&31
        s0 = csel=='uart' and uaddr==8; s1= csel=='uart' and uaddr==0x10
        mem_rdata = ((tx_busy<<9) if s1 else 0) if csel=='uart' else 0 if csel=='ram' else flash_rdata
        wr = wmask!=0
        d_in = rs2&255
        # uart peripheral
        urst = not resetn
        en = en16==0
        if urst:
            en16=13; d_in_uart=0; ctrl=0; tx_busy=0; txd=1; tx_cnt16=0
        else:
            n_en16 = 12 if en16==0 else en16-1
            nd_in = d_in if (s0 and wr) else d_in_uart
            nctrl = d_in if (s1 and wr) else ctrl
            ntx_busy,ntxd,ntx_cnt16,ntx_bit,ntxd_reg=tx_busy,txd,tx_cnt16,tx_bit,txd_reg
            if (ctrl>>3)&1 and not tx_busy:
                ntxd_reg=d_in_uart; ntx_bit=0; ntx_cnt16=0; ntx_busy=1
                sent.append((n,d_in_uart))
            if en:
                ntx_cnt16=(tx_cnt16+1)&15
                if tx_cnt16==0 and tx_busy:
                    ntx_bit=tx_bit+1
                    if tx_bit==0: ntxd=0
                    elif tx_bit==9: ntxd=1
                    elif tx_bit==10: ntx_bit=0; ntx_busy=0
                    else: ntxd=txd_reg&1; ntxd_reg=txd_reg>>1
            if (ctrl>>3)&1 and not tx_busy:   # tx_wr block assigned first; later block overrides cnt16
                pass
            en16=n_en16; d_in_uart=nd_in; ctrl=nctrl; led=(ctrl>>2)&1
            tx_busy,txd,tx_cnt16,tx_bit,txd_reg=ntx_busy,ntxd,ntx_cnt16,ntx_bit,ntxd_reg
        # cpu
        if not resetn:
            cst=WAITM; PC=0; rs1=rs2=0; wmask=0
        else:
            if cst==FETCH: wmask=0; cst=WAITI
            elif cst==WAITI:
                wmask=0
                if not rbusy:
                    rs1=RF[(mem_rdata>>15)&31]; rs2=RF[(mem_rdata>>20)&31]; instr=mem_rdata&~3; cst=EXEC
                    if trace and len(trans)<trace: pass
            elif cst==EXEC:
                wmask=15 if D['isStore'] else 0
                if D['isJALR']: PC=D['plus']&~1&M32
                elif D['isJAL'] or (D['isBranch'] and D['pred']): PC=D['PCimm']
                else: PC=(PC+4)&M32
                need = D['isLoad'] or D['isStore'] or (D['isALU'] and ((instr>>12)&7) in (1,5))
                cst=WAITM if need else FETCH
            elif cst==WAITM:
                wmask=0
                if not rbusy: cst=FETCH
    return sent,trans,RF

if __name__=='__main__':
    NOMBRE={'esp':'tolerante','catch':'real','miss':'sin_flanco'}
    for mode in ('esp','catch','miss'):
        random.seed(1)
        sent,trans,RF=run(600000,mode,rf_init=[random.getrandbits(32) for _ in range(32)])
        s=bytes(b for _,b in sent)
        print(f"== flash {NOMBRE[mode]}: {len(sent)} bytes por UART; primeros: {s[:40]!r}")
        if len(sent)>1: print("   ciclos de reloj entre bytes:", sent[1][0]-sent[0][0])
        for t in trans[:6]:
            c='--' if t['cmd'] is None else f"{t['cmd']:02X}"
            k='fetch' if t['kind']=='F' else 'carga'
            print(f"   {k} dir=0x{t['addr']:04X} fase={t['d']} flash recibe cmd={c} femto lee 0x{t['word']:08X}")
        print("   t1=0x%08X (debe ser 0x00400008)"%RF[6])
