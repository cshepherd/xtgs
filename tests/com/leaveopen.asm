; leaveopen.asm - create LEFT.TMP, write five bytes to it and exit WITHOUT
; closing it. The front end closes what a guest leaves open when the core
; returns, so the five bytes must be on the volume (the manifest's "disk"
; check). Exit code 0 if the create and the write worked, 1 if not.
        org 100h
        mov ah, 3Ch
        xor cx, cx
        mov dx, fname
        int 21h
        jc bad
        mov bx, ax
        mov ah, 40h
        mov cx, 5
        mov dx, fname
        int 21h
        jc bad
        mov ax, 4C00h
        int 21h
bad:    mov ax, 4C01h
        int 21h
fname   db 'LEFT.TMP', 0
