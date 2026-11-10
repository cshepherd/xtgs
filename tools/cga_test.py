#!/usr/bin/env python3
"""cga_test.py PROG.BAS|PROG.COM [seconds] - run a GW-BASIC program, or a
.COM program, under FreeDOS (Mode B) headless and render what the SHR
screen shows.

Builds a floppy whose AUTOEXEC runs GWBASIC on the program (GWBASIC in
the environment names another interpreter than third_party/gwbasic's:
SCREEN 7 needs Microsoft's 3.2x, docs/ega.md) or the .COM itself (VIDEO=CGA
in the environment: XTGS.CMD's line of that name, a PC with no EGA; TEXT=1:
print the buffer as the text screen as well), boots it in
MAME for the given emulated seconds (default 400; 500 has been enough
for a short program at stock speed, most of it the FreeDOS boot) and
writes build/cgatest/NAME.png. Prints the frame reached,
the non-zero bytes of the CGA framebuffer, how many SHR lines are in
640 mode and palette 0's first four entries. One run at a time: the
work files in build/cgatest are shared.

    python3 -I tools/cga_test.py third_party/freedos/fd/CGADEMO.BAS 500
"""
import os,sys,struct,subprocess
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
sys.path.insert(0,os.path.join(HERE,"mame")); sys.path.insert(0,HERE)
import mamerun, shr, symbols
bas=sys.argv[1]; T=float(sys.argv[2]) if len(sys.argv)>2 else 400
tag=os.path.splitext(os.path.basename(bas))[0]
FD=os.path.join(ROOT,"third_party","freedos","fd")
GW=os.environ.get("GWBASIC") or os.path.join(ROOT,"third_party","gwbasic","GWBASIC.EXE")
com=bas.upper().endswith(".COM")
work=os.path.join(ROOT,"build","cgatest"); os.makedirs(work,exist_ok=True)
if com:
    extra=["PROG.COM="+os.path.abspath(bas)]; line="PROG"
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
r=mamerun.run(po, waits=[(syms["mb_magic"],0x5A5A)],
  dumps=[("fb",0x2B8000,0x4000),("pal",0xE19E00,32),("shr",shr.SHR_BASE,shr.SHR_LEN)], seconds=T, settle=5)
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
