; jlink.asm - the translator's links (src/core/jit2.s, docs/jit.md): forward
; and backward conditional jumps, taken and not, near and beyond a native
; short branch, two loops that share a tail, a loop of one block. Only what
; the translator covers, and no jump that reads flags from another block.
; Not a benchmark: tools/jit_bench.py compares its registers with the
; interpreter's.
        cpu 8086
        org 0x100
        mov dx, OUTER
        mov bx, 0
        mov si, 0
        mov di, 0
        mov bp, 0
outer:  mov cx, 1000
inner:  test cx, 3
        jnz a                   ; forward, taken three times in four
        inc bx
        test cx, 4
        jz b                    ; forward, every other time here
        add si, 5
        add si, cx
        cmp si, 100
        jnz b
        inc di
b:      sub di, 1
        add di, bx
a:      add ax, cx
        add ax, si
        sub ax, 3
        add bp, ax
        add bp, di
        add bx, bp
        sub bx, 7
        add si, bx
        add si, 1
        add di, si
        add di, 2
        add ax, di
        add ax, bp
        sub si, 9
        add bp, si
        cmp ax, 77
        jz c                    ; forward, rare
        dec bp
c:      dec cx
        jnz inner               ; backward, further than a native short branch
        mov cx, 300
one:    dec cx                  ; a loop of one block
        jnz one
        mov cx, 50
two:    inc si
        test si, 1
        jz t2
        add bx, 1
t2:     dec cx
        jnz two
        dec dx
        jz done
        test dx, 0xFFFF         ; (dx is not 0: always taken, backward and far)
        jnz back
done:   hlt
back:   inc di
        test di, 0              ; always zero: a forward jump to the far one
        jz farj
        inc ax
farj:   cmp dx, 0
        jnz outer2
        hlt
outer2: cmp dx, 0x7F            ; never equal: on to the loop's head, backward
        jnz outer3
        hlt
outer3: test dx, 0xFFFF
        jz done
        sub bp, 1
        cmp bp, bp              ; (not covered: 39 /r falls back, one instruction)
        test dx, 0xFFFF
        jnz outer
        hlt
