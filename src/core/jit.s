*----------------------------------------------------------
* jit.s - M6 spike: dynamic-translation ceiling.
*
* Hand-written ("preassembled template") native 65816
* translations of the three register/memory/branch benchmark
* loops, run by the J command, measured against the
* interpreter running the same loops (B) by tools/jit_spike.py.
* This bounds the per-instruction ceiling of block
* translation for the kinds of code a real program (the
* FreeDOS boot) actually runs, before building a runtime
* translator. See docs/jit.md.
*
*   J R   reg.asm  (register ALU + loop)
*   J M   mem.asm  (three ModR/M memory operands an iteration)
*   J J   jmp.asm  (compare-and-branch)
*
* Guest registers live in the direct page (D = GUEST_DP):
* AX=$00 CX=$02 DX=$04 BX=$06 SI=$0C. Rules the templates
* follow, exactly as a block translator would:
*  - no fetch / decode / dispatch: straight-line native code;
*  - dead ALU flags elided (reg's add/sub, mem's add, jmp's
*    inc), because the next flag-setter overwrites them before
*    any branch reads them;
*  - the one live flag per loop (dec's or test's ZF) is the
*    65816 Z the native op leaves, read by BNE/BEQ, no table;
*  - memory operands recompute the effective address inline
*    each access (a basic-block JIT does no cross-iteration
*    hoisting), pEA = segbase + offset.
*
* Marks mirror bench_run: MB_RUNIDX = $BE57 running, $D04E
* done, so the frame-count timing matches tools/bench.py.
*----------------------------------------------------------
JIT_OUTER  =  4            ; outer iterations (match tools/bench.py --outer)

jit_run
 mx %00
 lda >MB_CMD+3             ; the J command's argument char
 and #$00FF
 cmp #'M'
 bne :notm
 jmp jit_mem
:notm
 cmp #'J'
 bne :notj
 jmp jit_jmp
:notj
 jmp jit_reg

*--- J R : reg.asm
*   inner: add ax,bx / sub bx,1 / dec cx / jnz / ... / dec dx / jnz
jit_reg
 mx %00
 lda #$BE57
 sta >MB_RUNIDX
 stz rAX
 stz rBX
 stz rCX
 lda #JIT_OUTER
 sta rDX
:outer
 stz rCX                   ; mov cx, 0
:inner
 lda rAX                   ; add ax, bx   (flags dead)
 clc
 adc rBX
 sta rAX
 lda rBX                   ; sub bx, 1    (flags dead)
 dec
 sta rBX
 dec rCX                   ; dec cx       (native Z = guest ZF)
 bne :inner                ; jnz inner
 dec rDX
 bne :outer
 lda #$D04E
 sta >MB_RUNIDX
 rts

*--- J M : mem.asm
*   bx=si=0x1000; inner: add [bx],ax / mov ax,[si+2] / mov [bx+4],ax / dec cx / jnz
jit_mem
 mx %00
 jsr set_all_bases         ; segments 0 -> bDS = GUEST_BASE
 lda #$BE57
 sta >MB_RUNIDX
 stz rAX
 lda #$1000
 sta rBX
 sta rSI
 lda #JIT_OUTER
 sta rDX
:outer
 stz rCX
:inner
 lda rBX                   ; add [bx], ax : pEA = bDS + BX
 clc
 adc bDS
 sta pSRC
 lda bDS+2
 adc #0
 sta pSRC+2
 lda [pSRC]                ; (flags dead)
 clc
 adc rAX
 sta [pSRC]
 lda rSI                   ; mov ax, [si+2] : pEA = bDS + SI + 2
 clc
 adc #2
 sta tmp0
 clc
 adc bDS
 sta pDST
 lda bDS+2
 adc #0
 sta pDST+2
 lda [pDST]
 sta rAX
 lda rBX                   ; mov [bx+4], ax : pEA = bDS + BX + 4
 clc
 adc #4
 sta tmp0
 clc
 adc bDS
 sta pSTK
 lda bDS+2
 adc #0
 sta pSTK+2
 lda rAX
 sta [pSTK]
 dec rCX                   ; dec cx ; jnz
 bne :inner
 dec rDX
 bne :outer
 lda #$D04E
 sta >MB_RUNIDX
 rts

*--- J J : jmp.asm
*   inner: test cx,1 / jz skip / inc ax / skip: dec cx / jnz
jit_jmp
 mx %00
 lda #$BE57
 sta >MB_RUNIDX
 stz rAX
 lda #JIT_OUTER
 sta rDX
:outer
 stz rCX
:inner
 lda rCX                   ; test cx, 1    (native Z = guest ZF)
 and #1
 beq :skip                 ; jz skip
 inc rAX                   ; inc ax        (flags dead)
:skip
 dec rCX                   ; dec cx
 bne :inner                ; jnz inner
 dec rDX
 bne :outer
 lda #$D04E
 sta >MB_RUNIDX
 rts
