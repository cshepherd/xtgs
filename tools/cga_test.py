#!/usr/bin/env python3
"""cga_test.py PROG.BAS|PROG.COM [seconds] - run a GW-BASIC program, or a
.COM program, under FreeDOS (Mode B) headless and render what the SHR
screen shows.

Builds a floppy whose AUTOEXEC runs GWBASIC on the program (GWBASIC in
the environment names another interpreter than third_party/gwbasic's:
SCREEN 7 needs Microsoft's 3.2x, docs/ega.md) or the .COM itself (VIDEO=CGA
in the environment: XTGS.CMD's line of that name, a PC with no EGA, and
VIDEO=TANDY a Tandy 1000, whose mode 08h, 09h or 0Ah is then judged against
the SHR by tools/tandyshr.py; ARGS=...: the .COM's command line; TEXT=1:
print the buffer as the text screen as well; CAP=1: the end of what the BIOS teletype printed), boots it in
MAME for the given emulated seconds (default 400; 500 has been enough
for a short program at stock speed, most of it the FreeDOS boot) and
writes build/cgatest/NAME.png. Prints the frame reached,
the non-zero bytes of the CGA framebuffer, how many SHR lines are in
640 mode and palette 0's first four entries; in a CGA graphics mode
also which of the sixteen colours the registers (and a Tandy's array)
make of the pixels, B800 and that palette judged against the SHR by
tools/cgashr.py. One run at a time: the work files in build/cgatest are
shared.

    python3 -I tools/cga_test.py third_party/freedos/fd/CGADEMO.BAS 500
"""
import os,sys,struct,subprocess
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
sys.path.insert(0,os.path.join(HERE,"mame")); sys.path.insert(0,HERE)
import mamerun, shr, symbols, tandyshr, cgashr
RES=0x050000; CAP_LEN=RES+0x800; CAP_BUF=RES+0x1000; CAP_MAX=0x7000    # src/include/pc.s
tandy=os.environ.get("VIDEO","").upper().startswith("T")
bas=sys.argv[1]; T=float(sys.argv[2]) if len(sys.argv)>2 else 400
tag=os.path.splitext(os.path.basename(bas))[0]
FD=os.path.join(ROOT,"third_party","freedos","fd")
GW=os.environ.get("GWBASIC") or os.path.join(ROOT,"third_party","gwbasic","GWBASIC.EXE")
com=bas.upper().endswith(".COM")
work=os.path.join(ROOT,"build","cgatest"); os.makedirs(work,exist_ok=True)
if com:
    extra=["PROG.COM="+os.path.abspath(bas)]; line=("PROG "+os.environ.get("ARGS","")).rstrip()
else:
    # PROG.BAS from the given file, CRLF
    prog=open(bas).read().replace("\n","\r\n")
    open(os.path.join(work,"PROG.BAS"),"w",newline="").write(prog)
    extra=["PROG.BAS="+os.path.join(work,"PROG.BAS"),"GWBASIC.EXE="+GW]; line="GWBASIC PROG.BAS"
open(os.path.join(work,"AUTOEXEC.BAT"),"w",newline="\r\n").write("@ECHO OFF\n"+line+"\n")
img=os.path.join(work,tag+".img")
subprocess.run([sys.executable,"-I",os.path.join(HERE,"make_fat12.py"),os.path.join(FD,"boot.bin"),img,
  "KERNEL.SYS="+os.path.join(FD,"KERNEL.SYS"),"COMMAND.COM="+os.path.join(FD,"COMMAND.COM"),
  "FDCONFIG.SYS="+os.path.join(FD,"FDCONFIG.SYS"),"AUTOEXEC.BAT="+os.path.join(work,"AUTOEXEC.BAT"),
  ]+extra,check=True,capture_output=True)
disk=os.path.join(work,"DISK#060000"); open(disk,"wb").write(open(img,"rb").read())
cmd=os.path.join(work,"XTGS.CMD#040000"); open(cmd,"w").write("D\r"+("VIDEO=%s\r"%os.environ["VIDEO"] if os.environ.get("VIDEO") else ""))
stage=os.path.join(ROOT,"build","stage"); po=os.path.join(work,tag+".po")
subprocess.run([os.path.join(HERE,"make_image.sh"),po,os.path.join(stage,"XTGS.SYSTEM#FF2000"),
  os.path.join(stage,"CORE#060000"),os.path.join(stage,"SVC#060000"),disk,cmd],check=True,capture_output=True)
syms=symbols.read(os.path.join(ROOT,"build","xtgs.lst"))
svc=symbols.read(os.path.join(ROOT,"build","svc.lst"))     # the colour-select register's three fields
assert svc["cga_pal"]==svc["cga_bg"]+2 and svc["cga_int"]==svc["cga_bg"]+4
r=mamerun.run(po, waits=[(syms["mb_magic"],0x5A5A)],
  dumps=[("fb",0x2B8000,0x4000),("pal",0xE19E00,32),("shr",shr.SHR_BASE,shr.SHR_LEN),
         ("caplen",CAP_LEN,2),("cap",CAP_BUF,CAP_MAX),
         ("tdy",RES+tandyshr.STATE,tandyshr.STATE_LEN),("tdymr",RES+tandyshr.MODEREQ,2),
         ("csel",svc["GUEST_DP"]+svc["cga_bg"],6),("bdam",0x200449,1)]+
        ([(f"tm{a:x}",0x200000+a,n) for a,n in tandyshr.REGIONS] if tandy else []),
  seconds=T, settle=5)
fb=bytes.fromhex(r["dumps"]["fb"]["hex"]); nz=sum(1 for b in fb if b)
pal=struct.unpack("<16H",bytes.fromhex(r["dumps"]["pal"]["hex"]))
png,l640=shr.render(bytes.fromhex(r["dumps"]["shr"]["hex"]))
out=os.path.join(work,tag+".png"); open(out,"wb").write(png)
print(f"[{tag}] frame={r['frame']} fb_nonzero={nz} 640mode_lines={l640} width={'640' if l640 else '320'}")
print(f"  SHR palette0 entries 0-3: {pal[0]:#06x} {pal[1]:#06x} {pal[2]:#06x} {pal[3]:#06x}")
print(f"  PNG -> {out}")
if os.environ.get("TEXT"):       # the buffer read as 80x25 text (a program that ends in mode 3)
    for y in range(25):
        row=bytes(fb[y*160+x*2] for x in range(80)).decode("cp437").rstrip("\0 ")
        if row: print(f"  {y:2}: {row}")
sd=bytes.fromhex(r["dumps"]["shr"]["hex"]); st=bytes.fromhex(r["dumps"]["tdy"]["hex"])
mr=bytes.fromhex(r["dumps"]["tdymr"]["hex"])[0]; bm=bytes.fromhex(r["dumps"]["bdam"]["hex"])[0]
# a CGA graphics mode (3D8h's bit 1; not the EGA's mode, nor a Tandy's 16 colours): the colours
if mr&2 and bm not in (8,9,0x0A,0x0D) and not (st[0] and tandyshr.mode(st,mr)):
    cm=6 if mr&0x10 else 4; csel=bytes.fromhex(r["dumps"]["csel"]["hex"])
    sel=csel[0]&15|(csel[4]&1)<<4|(csel[2]&1)<<5
    cols=cgashr.colours(sel,mr,cm,tandyshr.regs(st) if st[0] else None)
    print(f"  CGA mode {5 if cm==4 and mr&4 else cm}: 3D8h {mr:02X}, 3D9h {sel:02X}, the BDA's mode {bm:02X}h, colours {' '.join(map(str,cols))}; "+
          (f"{len(cgashr.mismatches(fb,sd,cm))} of 16000 bytes not on the screen, {len(cgashr.palette(sd,cm,cols))} palette entries wrong"
           if cgashr.is_cga(sd,cm) else "the SHR is not in that mode"))
if tandy:                        # the Tandy's registers, and a mode of its own against the screen
    print(f"  Tandy: on={st[0]} page register {tandyshr.page_reg(st):02X}, pages in slots {tandyshr.slots(st)}, "
          f"{st[6]|st[7]<<8} moves of 16K, mode register {tandyshr.regs(st)[3]:02X}, "
          f"palette {tandyshr.regs(st)[16:32].hex().upper()} through {tandyshr.regs(st)[1]:02X}")
    tm=tandyshr.mode(st,bytes.fromhex(r["dumps"]["tdymr"]["hex"])[0])
    if tm and tandyshr.shows(sd,tm):
        mem={a:bytes.fromhex(r["dumps"][f"tm{a:x}"]["hex"]) for a,_n in tandyshr.REGIONS}
        bad=tandyshr.mismatches(mem,st,sd,tm); badp=tandyshr.palette(st,sd,tm)
        print(f"  as mode {tm:02X}h: {len(bad)} of 32000 bytes not on the screen"+(f" (first line,byte {bad[0]})" if bad else "")+
              f", {len(badp)} palette entries wrong")
if os.environ.get("CAP"):        # what the BIOS teletype printed, the end of it
    n=struct.unpack("<H",bytes.fromhex(r["dumps"]["caplen"]["hex"]))[0]
    cap=bytes.fromhex(r["dumps"]["cap"]["hex"])[:n]
    print(f"  teletype ({n} bytes), the end: {cap[-300:]!r}")
