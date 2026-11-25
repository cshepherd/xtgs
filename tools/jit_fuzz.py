#!/usr/bin/env python3
"""The translator against the interpreter (docs/jit.md): random loops, run both ways.

    jit_fuzz.py [--seed N] [--runs R] [--cases C] [--keep] [--show CASE]

A run is one .COM program of C loops (tests' stub DOS, command C). Each loop
sets the registers and a buffer to known values, goes round 40 times (the
translator takes it at the sixteenth) and prints a sum of every register,
the flags and the buffer. The program is run without JIT=ON and with it, and
the two outputs must be the same: the first loop that differs is printed.
The loops are made of what the translator covers and of what it gives back
to the interpreter (the shifts, ADC, PUSHF...), with memory operands of every
form inside the buffer, jumps ahead on every condition, the string
instructions, a segment prefix now and then.  Work files in build/jitfuzz/.
"""
import argparse
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
sys.path.insert(0, HERE)
import mamerun  # noqa: E402
import symbols  # noqa: E402

WORK = os.path.join(ROOT, "build", "jitfuzz")
RES_BASE = 0x050000
CAP_LEN, CAP_BUF = RES_BASE + 0x800, RES_BASE + 0x1000
ITER = 40
R16 = ["ax", "dx"]
R8 = ["al", "ah", "dl", "dh"]
SRC16 = ["ax", "dx", "cx", "bx", "si", "di", "bp"]
SRC8 = ["al", "ah", "dl", "dh", "cl", "ch", "bl", "bh"]
ALU = ["add", "sub", "and", "or", "xor", "cmp"]
JCC = ["jo", "jno", "jb", "jae", "jz", "jnz", "jbe", "ja", "js", "jns", "jl", "jge", "jle", "jg", "jp", "jnp"]


class Gen:
    def __init__(self, rnd):
        self.r = rnd
        self.lab = 0

    def mem(self):
        r = self.r
        k = r.randrange(9)
        d8 = r.randrange(-40, 40) & ~1
        seg = "es:" if r.random() < 0.1 else ""
        return seg + ["bx", "si", "di", f"bp{d8:+d}", f"bx{d8:+d}", f"si{d8:+d}", "buf+%d" % (2 * r.randrange(200, 300)),
                      "bx+si-(buf+450)", f"bx+di-(buf+470){d8:+d}"][k]

    def ins(self):
        """one or a few lines of a loop's body"""
        r = self.r
        k = r.randrange(100)
        w = r.random() < 0.6
        regs, srcs, size = (R16, SRC16, "word") if w else (R8, SRC8, "byte")
        imm = r.choice([0, 1, 2, 0x7F, 0x80, 0xFF, r.randrange(256)]) if not w else \
            r.choice([0, 1, 0x7F, 0x80, 0xFF, 0x7FFF, 0x8000, 0xFFFF, r.randrange(65536)])
        if r.random() < 0.22:
            return self.more(w, regs, srcs, size, imm)
        if k < 14:
            return [f"{r.choice(ALU + ['test'])} {r.choice(regs)}, {r.choice(srcs)}"]
        if k < 22:
            return [f"{r.choice(ALU + ['test'])} {r.choice(regs)}, {imm}"]
        if k < 30:
            return [f"{r.choice(ALU)} {r.choice(regs)}, [{self.mem()}]"]
        if k < 38:
            return [f"{r.choice(ALU + ['test'])} [{self.mem()}], {r.choice(srcs)}"]
        if k < 43:
            return [f"{r.choice(ALU + ['test'])} {size} [{self.mem()}], {imm}"]
        if k < 49:
            return [r.choice([f"mov {r.choice(regs)}, {r.choice(srcs)}", f"mov {r.choice(regs)}, {imm}",
                              f"mov {r.choice(regs)}, [{self.mem()}]", f"mov [{self.mem()}], {r.choice(srcs)}",
                              f"mov {size} [{self.mem()}], {imm}", f"mov {'ax' if w else 'al'}, [buf+{2 * r.randrange(250)}]",
                              f"mov [buf+{2 * r.randrange(250)}], {'ax' if w else 'al'}"])]
        if k < 55:
            return [r.choice([f"inc {r.choice(regs)}", f"dec {r.choice(regs)}", f"inc {size} [{self.mem()}]",
                              f"dec {size} [{self.mem()}]", "inc si", "dec di", "inc di", "dec si"])]
        if k < 59:
            return [r.choice([f"not {r.choice(regs)}", f"not {size} [{self.mem()}]", f"neg {r.choice(regs)}",
                              "xchg ax, dx", "xchg al, dh", "cbw", "cwd", "nop",
                              f"lea {r.choice(R16)}, [{self.mem().replace('es:', '')}]"])]
        if k < 63:
            a, b = r.choice(SRC16), r.choice(R16)
            return [f"push {a}"] + (self.ins() if r.random() < 0.5 else []) + [f"pop {b}"]
        if k < 71:
            return [r.choice(["lodsb", "lodsw", "stosb", "stosw", "movsb", "movsw", "es lodsb"])]
        if k < 77:
            return [r.choice([f"shl {r.choice(regs)}, 1", f"shr {r.choice(regs)}, 1", f"sar {r.choice(regs)}, 1",
                              f"rol {r.choice(regs)}, 1", f"rcr {r.choice(regs)}, 1", f"shl {r.choice(regs)}, cl",
                              f"shr {size} [{self.mem()}], 1"])]
        if k < 82:
            return [r.choice([f"adc {r.choice(regs)}, {r.choice(srcs)}", f"sbb {r.choice(regs)}, {imm}",
                              "pushf\n        pop dx", "lahf", "sahf", "cmc", "clc", "stc"])]
        if k < 84:
            return ["call sub1"]
        if k < 86:
            return [r.choice(["mov bx, buf+400", "mov bp, buf+300", "mov es, [dsval]", "push ds\n        pop es"])]
        # a jump ahead over the next one or two
        self.lab += 1
        lab = f".f{self.lab}"
        body = self.ins() + (self.ins() if r.random() < 0.4 else [])
        return [f"{r.choice(JCC)} {lab}"] + body + [f"{lab}:"]

    def more(self, w, regs, srcs, size, imm):
        """what the second translator added: shifts, ADC and SBB, NEG, calls, the segment registers"""
        r = self.r
        k = r.randrange(100)
        sh = r.choice(["shl", "shr", "sar", "rol", "ror", "rcl", "rcr"])
        if k < 22:
            return [f"{sh} {r.choice(regs)}, 1"]
        if k < 28:
            return [f"{sh} {size} [{self.mem()}], 1"]
        if k < 38:
            return ["push cx", f"mov cl, {r.choice([0, 1, 2, 3, 4, 7, 8, 9, 15, 16, 17, 31])}", f"{sh} {r.choice(regs)}, cl",
                    "pop cx"]
        if k < 50:
            return [r.choice([f"adc {r.choice(regs)}, {r.choice(srcs)}", f"sbb {r.choice(regs)}, {r.choice(srcs)}",
                              f"adc {r.choice(regs)}, {imm}", f"sbb {r.choice(regs)}, {imm}",
                              f"adc {r.choice(regs)}, [{self.mem()}]", f"sbb [{self.mem()}], {r.choice(srcs)}",
                              f"adc {size} [{self.mem()}], {imm}"])]
        if k < 56:
            return [r.choice([f"neg {r.choice(regs)}", f"neg {size} [{self.mem()}]", "cmc", "stc", "clc"])]
        if k < 62:
            return [f"xchg {r.choice(regs)}, [{self.mem()}]"]
        if k < 76:
            return [r.choice(["call sub1", "call sub2", "push ax\n        call sub3", "push cs\n        call sub4",
                              "call sub5", "call sub6", "call [vec]", "mov bp, sub1\n        call bp\n        mov bp, buf+300"])]
        if k < 86:
            return [r.choice(["push ds\n        pop es", "mov es, [dsval]", "push es\n        pop ds", "mov dx, es",
                              "push cs\n        pop es", "mov ax, ds\n        mov es, ax"])]
        if k < 92:
            return ["pushf", "pop dx"] if r.random() < 0.5 else ["lahf"]
        self.lab += 1
        lab = f".g{self.lab}"
        return [f"mov word [jv], {lab}", "jmp [jv]", "inc dx", f"{lab}:"]

    def case(self, n):
        r = self.r
        out = [f"case{n}:", "        call reset"]
        for reg in ("ax", "dx"):
            out.append(f"        mov {reg}, {r.randrange(65536)}")
        closer = r.randrange(4)
        out.append(f"        mov cx, {ITER}" if closer in (0, 1) else f"        mov cx, {r.randrange(65536)}")
        out.append(f"        mov byte [cnt], {ITER}")
        out.append(f"        cmp ax, {r.randrange(65536)}")      # the flags to begin with
        out.append(".top:")
        body = []
        for _ in range(r.randrange(3, 11)):
            body += self.ins()
        out += ["        " + l if not l.endswith(":") else l for l in body]
        out += [["        loop .top"], ["        dec cx", "        jnz .top"], ["        dec byte [cnt]", "        jnz .top"],
                ["        sub byte [cnt], 1", "        ja .top"]][closer]
        out += ["        call fold", ""]
        return out


PRE = """; generated by tools/jit_fuzz.py: seed {seed}, run {run}
        cpu 8086
        org 100h
        cld
        mov [dsval], ds
        mov [fp+2], ds
        xor ax, ax              ; INT 3 comes back at once
        mov es, ax
        mov word [es:0Ch], int3
        mov [es:0Eh], cs
"""
POST = """        call ticks
        mov ax, 4C00h
        int 21h

ticks:  push ds                 ; three ticks of the clock at 0040:006C, waited for in a loop that does
        xor ax, ax              ; nothing else: the slot has to get its turn while translated code runs
        mov ds, ax
        mov cx, 3
.n:     mov ax, [46Ch]
.w:     cmp ax, [46Ch]
        je .w
        loop .n
        pop ds
        mov dl, 'T'
        mov ah, 2
        int 21h
        ret

int3:   inc dx
        iret
sub1:   xor al, 5Ah
        ret
sub2:   add dx, ax
        adc ax, dx
        ret
sub3:   push bp
        mov bp, sp
        add ax, [bp+4]
        pop bp
        ret 2
sub4:   xor dx, ax
        retf
sub5:   push cx
        mov cx, 5
.l:     add ax, cx
        rol dx, 1
        loop .l
        pop cx
        ret
sub6:   call sub1
        call sub2
        jz .z
        inc dx
.z:     ret
sub7:   add ax, 0101h
        ret
sub8:   inc word [.n+2]         ; a routine that changes itself, then runs what it changed
.n:     add dx, 100h
        ret

reset:  push cs                 ; the buffer as it always begins, the pointers into it
        pop ds
        push ds
        pop es
        mov word [fp], buf+640
        cld
        mov di, buf
        mov cx, 512
        mov ax, 1234h
.f:     stosw
        add ax, 0B5C7h
        loop .f
        mov bx, buf+400
        mov si, buf+500
        mov di, buf+600
        mov bp, buf+300
        ret

fold:   pushf                   ; everything into a word, and the word printed
        cld
        mov [cs:save], ax
        pop ax
        and ax, 08D5h
        mov [cs:sum], ax
        mov ax, [cs:save]
        call .mix
        mov ax, dx
        call .mix
        mov ax, cx
        call .mix
        mov ax, bx
        call .mix
        mov ax, si
        call .mix
        mov ax, di
        call .mix
        mov ax, bp
        call .mix
        mov ax, cs
        mov ds, ax
        mov es, ax
        mov si, buf
        mov cx, 512
.b:     lodsw
        call .mix
        loop .b
        mov bx, [sum]
        mov cx, 4
.h:     rol bx, 1
        rol bx, 1
        rol bx, 1
        rol bx, 1
        mov dl, bl
        and dl, 0Fh
        add dl, '0'
        cmp dl, '9'
        jbe .d
        add dl, 7
.d:     mov ah, 2
        int 21h
        loop .h
        mov dl, ' '
        mov ah, 2
        int 21h
        ret
.mix:   add [cs:sum], ax
        rol word [cs:sum], 1
        ret

dsval:  dw 0
fp:     dw buf+640, 0
vec:    dw sub2
jv:     dw 0
save:   dw 0
sum:    dw 0
cnt:    db 0, 0
cnt2:   db 0, 0
buf:    times 1024 db 0
"""


MICRO = """sub ax, 127|mov ah, [bx]|test ax, 32767|clc|and byte [bx+si-(buf+450)], 1|mov [buf+388], ax|push bx;pop ax
sub ax, [si]|sub dl, dl|and ax, si|xor dx, dx|add ax, dx|add al, dh|cmp ax, dx;jb .x;inc dx;.x:|cmp al, 7;jz .x;inc dx;.x:
mov ax, dx|mov dl, ah|mov ax, 1234|mov dh, 9|mov ax, [bx]|mov [bx], ax|mov [si+4], dl|mov word [di], 77|mov byte [bp-2], 5
inc ax|dec dx|inc dl|dec ah|inc word [bx]|dec byte [si]|or ax, 0x8000;js .x;inc dx;.x:|test dl, 1;jnz .x;inc ax;.x:
lodsb|lodsw|stosb|stosw|movsb|movsw|es lodsb|lea ax, [bx+si-(buf+450)]|lea dx, [bp+6]|not ax|not byte [bx]|xchg ax, dx|cbw|cwd
shl ax, 1|adc ax, dx|pushf;pop dx|lahf|call sub1|cmp ax, 0x9000;jl .x;inc dx;.x:|cmp ax, 0x9000;jg .x;inc dx;.x:
cmp ax, dx;jbe .x;inc dx;.x:|cmp ax, dx;ja .x;inc dx;.x:|add ax, 0x4000;jo .x;inc dx;.x:|add ax, dx;jc .x;inc dx;.x:
sub ax, dx;jle .x;inc dx;.x:|sub ax, dx;jge .x;inc dx;.x:|and ax, dx;jle .x;inc dx;.x:|and ax, dx;jg .x;inc dx;.x:
inc ax;jz .x;inc dx;.x:|dec ax;js .x;inc dx;.x:|dec ax;jo .x;inc dx;.x:|cmp ax, dx;mov cx, cx;jb .x;inc dx;.x:
add ax, [bx];jnc .x;inc dx;.x:|cmp byte [si], 0x34;jz .x;inc dx;.x:|test word [bx], 0x8000;jnz .x;inc dx;.x:
es mov ax, [bx]|es mov [bx], dl|add [bx], ax|sub [di], dl|xor [bp+4], ax|cmp [bx], ax;jz .x;inc dx;.x:|mov al, [buf+10]|mov [buf+12], al
push ax;push dx;pop ax;pop dx|sub byte [cnt2], 1|add word [buf+20], 3|cmp ax, dx;jp .x;inc dx;.x:|std;lodsb;cld|stc;adc ax, 0
shl ax, 1|shr dx, 1|sar ax, 1|rol ax, 1|ror dx, 1|rcl ax, 1|rcr dx, 1|shl al, 1|shr dh, 1|sar al, 1|rol dl, 1|ror ah, 1|rcl al, 1|rcr dh, 1
shl word [bx], 1|shr byte [si], 1|sar word [di], 1|rol byte [bx], 1|ror word [si], 1|rcl word [bx], 1|rcr byte [di], 1|sar byte [bx], 1
shl ax, 1;jc .x;inc dx;.x:|shr ax, 1;jz .x;inc dx;.x:|sar ax, 1;js .x;inc dx;.x:|shl ax, 1;jo .x;inc dx;.x:|shr ax, 1;jo .x;inc dx;.x:
rol ax, 1;jo .x;inc dx;.x:|rcr ax, 1;jo .x;inc dx;.x:|ror al, 1;jc .x;inc dx;.x:|rcl dx, 1;jz .x;inc ax;.x:|shl al, 1;jl .x;inc dx;.x:
shl ax, 1;pushf;pop dx|shr dx, 1;pushf;pop ax|sar al, 1;lahf|rol dx, 1;pushf;pop ax|rcr al, 1;pushf;pop dx|ror dx, 1;lahf|rcl ax, 1;lahf
push cx;mov cl, 3;shl ax, cl;pop cx|push cx;mov cl, 0;shr dx, cl;pop cx|push cx;mov cl, 17;sar ax, cl;pop cx|push cx;mov cl, 5;rol dx, cl;pop cx
push cx;mov cl, 4;ror al, cl;pop cx|push cx;mov cl, 9;rcl ax, cl;pop cx|push cx;mov cl, 3;rcr dh, cl;pop cx|push cx;mov cl, 1;shl dl, cl;pop cx
push cx;mov cl, 2;shl ax, cl;pushf;pop si;pop cx|push cx;mov cl, 3;rcr dx, cl;pushf;pop si;pop cx|push cx;mov cl, 0;rol ax, cl;pushf;pop si;pop cx
push cx;mov cl, 7;shr ax, cl;jc .x;inc dx;.x:;pop cx|push cx;mov cl, 2;sar dx, cl;lahf;pop cx|push cx;mov cl, 18;shl ax, cl;lahf;pop cx
add ax, dx;adc dx, ax|sub ax, dx;sbb dx, 7|cmp ax, dx;adc ax, 0|stc;adc al, dl|add [bx], ax;adc [bx+2], dx|sub [si], dl;sbb [si+1], dh
shl ax, 1;rcl dx, 1|shr dx, 1;rcr ax, 1|sub ax, dx;rcl dx, 1|add ax, dx;sbb dx, dx|adc ax, dx;jc .x;inc dx;.x:|sbb ax, dx;jb .x;inc dx;.x:
add al, dl;adc ah, dh|sub al, 3;sbb ah, 0|shl ax, 1;rcl dx, 1;rcl word [bx], 1|adc ax, [bx]|sbb dl, [si]|adc word [bx], 5|sbb byte [di], 200
cmp ax, dx;sbb ax, ax|add ax, 0x9000;adc dx, 0;pushf;pop si|sub ax, dx;sbb dx, ax;lahf|cmc;adc ax, 0|cmp ax, dx;cmc;sbb dx, 0
neg ax|neg dl|neg word [bx]|neg byte [si]|neg dx;jc .x;inc ax;.x:|neg ax;sbb dx, 0|neg al;pushf;pop dx|not ax;neg ax
xchg ax, [bx]|xchg dl, [si]|xchg [di+2], dx|xchg ah, al
push ds;pop es|mov ax, ds;mov es, ax;mov [es:bx], dx|mov dx, es|mov [bx], ds|mov es, [dsval];es mov ax, [si]|push es;push cs;pop es;pop es
les di, [fp];mov [es:di], al;inc word [fp]|lds si, [fp];lodsw|push ss;pop es;push cs;pop ds|mov ax, cs;mov ds, ax|mov [buf+30], cs
call sub1|call sub2|push ax;call sub3|mov bp, sub1;call bp;mov bp, buf+300|call [vec]|mov word [jv], .b;jmp [jv];inc dx;.b:
push cs;call sub4|call sub5|call sub1;call sub2;call sub1|mov si, sub2;call si;mov si, buf+500|call sub6|jmp .y;.z:;inc ax;jmp .w;.y:;jmp .z;.w:
inc byte [.i+1];.i:;add ax, 0x1111|inc byte [sub7+1];call sub7|add byte [.j+1], 3;sub dx, ax;.j:;mov al, 0|call sub8
mov si, .k;inc byte [si+2];.k:;xor dx, 0x1100|push ax;push dx;mov bp, sp;add word [bp], 3;add [bp+2], dx;pop dx;pop ax;mov bp, buf+300
push ax;pop word [bx]|push dx;pop word [buf+6]|push word [si];pop word [di]|push cx;mov cx, 5;rep movsb;pop cx|push cx;mov cx, 3;rep stosw;pop cx
push cx;mov cx, 4;rep lodsb;pop cx|push cx;mov cx, 9;repne scasb;pop cx|push cx;mov cx, 0;rep movsw;pop cx|push cx;push di;mov di, .q+1;mov cx, 1;rep stosb;pop di;pop cx;.q:;mov al, 7
push cx;push di;mov di, sub7+1;mov cx, 2;rep stosb;pop di;pop cx;call sub7|push cx;std;mov cx, 3;rep movsb;cld;pop cx|pushf;popf|cli;sti|int 3
jmp .s;.v:;db 0;.s:;inc byte [.v];add al, [.v]|jmp .s;.v:;db 0;.s:;nop;mov word [.v], 0x4000|jmp .s;.v:;db 0, 0;.s:;add word [.v], 3;add ax, [.v]
mov bx, sp;sub sp, 300;push ax;push dx;pop dx;pop ax;mov sp, bx|mov bx, ss;mov ss, bx;push ax;pop dx|push ss;pop ss;push dx;pop ax
cli;mov bx, sp;mov sp, buf+200;push ax;push dx;pop dx;pop ax;mov sp, bx;sti|cli;mov bx, sp;mov sp, buf+201;push ax;push dx;pop ax;pop dx;mov sp, bx;sti
cli;mov bx, sp;mov sp, .t+2;mov si, 0x9040;push si;mov sp, bx;sti;.t:;nop;nop|cli;mov bx, sp;mov sp, buf+0x102;push ax;push dx;push ax;pop dx;pop dx;pop dx;mov sp, bx;sti
cmp ax, dx;jmp .f;times 50 nop;.f:;jc .x;inc dx;.x:|add ax, dx;jmp .f;times 50 nop;.f:;mov bx, ax;sub bx, dx;adc ax, 0|add ax, 0x9000;jmp .f;times 50 nop;.f:;inc dx;adc ax, 0
jmp .o;.r:;adc dx, 0;ret;.o:;add ax, 0x9000;call .r|jmp .o;.r:;mov bx, 5;add bx, ax;ret;.o:;add ax, 0x9000;call .r;adc dx, bx|sub ax, dx;jns .f;neg ax;jmp .g;times 50 nop;.f:;sbb dx, 0;.g:
add ax, 0x9000;jmp .f;times 50 nop;.f:;stc;adc dx, 0;xor byte [.f], 0x69|add ax, dx;jmp .f;times 50 nop;.f:;jmp .h;times 50 nop;.h:;xor bx, bx;adc ax, bx|add ax, 0x9000;jmp .f;times 50 nop;.f:;lahf;mov dl, ah
add ax, 0x9000;jmp .f;times 50 nop;.f:;cmp dx, 5;adc ax, 0;xor byte [.f+1], 0x38|sub ax, 3;jmp .f;times 50 nop;.f:;mov bx, [buf+2];push bx;pop dx;rcl dx, 1|add ax, dx;jmp .f;times 50 nop;.f:;dec dx;jmp .h;times 50 nop;.h:;jc .x;inc ax;.x:
jmp .s;.v:;db 0;.s:;nop;mov byte [.s], 0x40|jmp .s;.v:;db 0, 0, 0;.s:;nop;mov word [.v+2], 0x4200|jmp .s;.s:;mov byte [.e], 0x42;nop;.e:;nop
fild word [bx];fiadd word [si];fistp word [bx+2]|fild word [buf+400];fld1;faddp st1, st0;fistp word [buf+400]|fild word [si];fnstsw [buf+402];fstp st0
jmp .s;.v:;dw 0x4040;.s:;fild word [.v];fistp word [.e];.e:;nop;nop
"""


def build(seed, run, cases, micro=False):
    g = Gen(random.Random(seed * 1000 + run))
    lines, per = [PRE.format(seed=seed, run=run)], []
    if micro:
        bodies = [b for line in MICRO.strip().split("\n") for b in line.split("|")]
        for n, body in enumerate(bodies):
            c = [f"case{n}:", "        call reset", "        mov ax, 0x1234", "        mov dx, 0x8765", f"        mov cx, {ITER}",
                 "        cmp ax, 5", ".top:"]
            c += [l if l.endswith(":") else "        " + l for l in body.split(";")]
            c += ["        loop .top", "        call fold", ""]
            per.append(c)
            lines += c
        return "\n".join(lines) + "\n" + POST, per
    for n in range(cases):
        c = g.case(n)
        per.append(c)
        lines += c
    return "\n".join(lines) + "\n" + POST, per


SMALL = False                                               # --small: the first bank of code holds next to nothing


def execute(binary, jit, syms):
    stage = os.path.join(ROOT, "build", "stage")
    staged = os.path.join(WORK, "FUZZ.COM#060000")
    with open(binary, "rb") as f, open(staged, "wb") as g:
        g.write(f.read())
    cmd = os.path.join(WORK, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("C FUZZ.COM\r" + ("JIT=ON\r" if jit else ""))
    image = os.path.join(WORK, "fuzz%d.po" % jit)
    files = [os.path.join(stage, n) for n in ("XTGS.SYSTEM#FF2000", "CORE#060000", "SVC#060000")] + [staged, cmd]
    if jit:
        files.append(os.path.join(stage, "JIT#060000"))
    env = {k: v for k, v in os.environ.items() if k != "XTGS_JIT"}
    subprocess.run([os.path.join(HERE, "make_image.sh"), image] + files, check=True, capture_output=True, env=env)
    dumps = [("len", CAP_LEN, 2), ("cap", CAP_BUF, 0x1000)]
    jt = symbols.read(os.path.join(ROOT, "build", "jit.lst"))
    if jit and "jt_stats" in jt:
        dumps.append(("stats", jt["jt_stats"], 20))
    extra = None
    if jit and SMALL and "c_lim" in jt:
        # the translator's first bank of code is full after a few pieces (c_lim, jit.s): nearly everything is made
        # in the second, and what runs goes from one bank to the other all the time
        import layout
        extra = {"top": "", "tail": """
local xs = manager.machine.devices[":maincpu"].spaces["program"]
while true do
    emu.wait(0.02)
    if xs:read_u16(%d) ~= %d then xs:write_u16(%d, %d) end
end
""" % (layout.to_actual(jt["c_lim"]), (jt["jt_cache"] & 0xFFFF) + 0x0500, layout.to_actual(jt["c_lim"]),
       (jt["jt_cache"] & 0xFFFF) + 0x0500)}
    r = mamerun.run(image, waits=[(syms["mb_magic"], 0x5A5A)], dumps=dumps, seconds=600, settle=2, zip=True, extra=extra)
    os.remove(image)
    n = int.from_bytes(bytes.fromhex(r["dumps"]["len"]["hex"]), "little")
    out = bytes.fromhex(r["dumps"]["cap"]["hex"])[:n].decode("latin-1")
    stats = None
    if "stats" in r["dumps"]:
        b = bytes.fromhex(r["dumps"]["stats"]["hex"])
        stats = [b[i] | b[i + 1] << 8 for i in range(0, 20, 2)]
    return r["status"], r["frame"], out, stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--cases", type=int, default=40)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--show", type=int)
    ap.add_argument("--micro", action="store_true", help="one instruction form a loop, from a fixed list")
    ap.add_argument("--small", action="store_true",
                    help="the translator's first bank of code made to hold a few pieces only: the second bank's turn")
    args = ap.parse_args()
    global SMALL
    SMALL = args.small
    os.makedirs(WORK, exist_ok=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    bad = 0
    for run in range(args.runs):
        src, per = build(args.seed, run, args.cases, args.micro)
        if args.micro:
            args.cases = len(per)
        asm = os.path.join(WORK, "fuzz.asm")
        with open(asm, "w") as f:
            f.write(src)
        if args.show is not None:
            print("\n".join(per[args.show]))
            return
        binary = os.path.join(WORK, "fuzz.com")
        subprocess.run(["nasm", "-f", "bin", "-o", binary, asm], check=True)
        s0, f0, o0, _ = execute(binary, False, syms)
        s1, f1, o1, st = execute(binary, True, syms)
        a, b = o0.split(), o1.split()
        line = f"seed {args.seed} run {run}: {len(a)} loops, {f0} frames interpreted, {f1} translated"
        if st:
            line += (f" ({st[0]} pieces translated, {st[1]} refused, {st[3]} found changed, {st[4]} stores beside code, "
                     f"{st[7]} pages of data and code, {st[6]} misses, the epoch on {st[8]} times, {st[9]} compares)")
        tick = [x for x in (a, b) if x and x[-1].endswith("T")]
        a = [x.rstrip("T") for x in a if x != "T"]
        b = [x.rstrip("T") for x in b if x != "T"]
        if len(tick) != 2:
            print(line + ": the wait for the clock's ticks did not end both ways")
            bad += 1
        if s0 != "hit" or s1 != "hit" or len(a) != args.cases:
            print(line + f": did not finish ({s0}, {s1}; {len(a)} and {len(b)} sums)")
            bad += 1
        if a == b and len(a) == args.cases:
            print(line + ": the same")
            continue
        bad += 1
        first = True
        for n in range(max(len(a), len(b))):
            if n >= len(a) or n >= len(b) or a[n] != b[n]:
                if first:
                    print(line + f": loop {n} differs ({a[n] if n < len(a) else '-'} interpreted, "
                          f"{b[n] if n < len(b) else '-'} translated)")
                    print("\n".join(per[n]) if n < len(per) else "")
                    first = False
                elif args.micro:
                    print(f"  and loop {n}: " + "; ".join(l.strip() for l in per[n][7:-3]))
                else:
                    break
        if not args.keep:
            break
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
