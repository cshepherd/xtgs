; fileops.asm - the handle file functions end to end, on files the program
; makes itself: create/write/close, open/lseek/read/write, rename, get
; attributes, find first/next, mkdir, a file in the directory, delete,
; rmdir. Every step prints a line, so the console output is the test.
        org 100h

%macro  say 1
        mov dx, %1
        mov ah, 9
        int 21h
%endmacro
%macro  dos 1                   ; AH = %1, INT 21h; on CF report the step and quit
        mov ah, %1
        int 21h
        jnc %%ok
        mov [errc], ax
        jmp fail
%%ok:
%endmacro

        ; 1. create T1.TMP, write the alphabet, close
        mov byte [step], '1'
        mov dx, t1
        xor cx, cx
        dos 3Ch
        mov [h], ax
        mov bx, ax
        mov cx, 26
        mov dx, alpha
        dos 40h
        call number             ; bytes written
        mov bx, [h]
        dos 3Eh
        say m_made

        ; 2. open read/write: size, seek to 10, read 5, write "xyz" at 15
        mov byte [step], '2'
        mov dx, t1
        mov al, 2
        dos 3Dh
        mov [h], ax
        mov bx, ax
        mov al, 2               ; lseek to the end: DX:AX = the size
        xor cx, cx
        xor dx, dx
        dos 42h
        call number
        say m_size
        mov bx, [h]
        mov al, 0
        xor cx, cx
        mov dx, 10
        dos 42h
        mov bx, [h]
        mov cx, 5
        mov dx, buf
        dos 3Fh
        call show               ; AX bytes of buf
        mov bx, [h]
        mov cx, 3
        mov dx, xyz
        dos 40h
        mov bx, [h]
        mov al, 1               ; lseek 0 from here: the position (18)
        xor cx, cx
        xor dx, dx
        dos 42h
        call number
        say m_pos
        mov bx, [h]
        dos 3Eh

        ; 3. rename; the old name is gone, the new one has the bytes
        mov byte [step], '3'
        mov dx, t1
        push ds
        pop es
        mov di, t2
        dos 56h
        mov dx, t1
        mov ax, 3D00h
        int 21h
        jc .gone
        jmp fail
.gone:  say m_gone
        mov dx, t2
        mov al, 0
        dos 3Dh
        mov [h], ax
        mov bx, ax
        mov cx, 64
        mov dx, buf
        dos 3Fh
        call show
        mov bx, [h]
        mov cx, 64              ; at the end: zero bytes
        mov dx, buf
        dos 3Fh
        call number
        say m_eof
        mov bx, [h]
        dos 3Eh

        ; 4. attributes of a file
        mov byte [step], '4'
        mov dx, t2
        mov al, 0
        dos 43h
        test cx, 10h
        jz .file
        jmp fail
.file:  say m_attr

        ; 5. a second file, then find first/next over T?.TMP
        mov byte [step], '5'
        mov dx, t3
        xor cx, cx
        dos 3Ch
        mov [h], ax
        mov bx, ax
        mov cx, 3
        mov dx, xyz
        dos 40h
        mov bx, [h]
        dos 3Eh
        mov dx, pat
        call list

        ; 6. a directory with a file in it
        mov byte [step], '6'
        mov dx, subd
        dos 39h
        mov dx, subd
        mov al, 0
        dos 43h
        test cx, 10h
        jnz .isdir
        jmp fail
.isdir: say m_dir
        mov dx, inner
        xor cx, cx
        dos 3Ch
        mov [h], ax
        mov bx, ax
        mov cx, 7
        mov dx, alpha
        dos 40h
        mov bx, [h]
        dos 3Eh
        mov dx, subpat
        call list
        mov dx, subd            ; not empty: rmdir must fail
        mov ah, 3Ah
        int 21h
        jc .full
        jmp fail
.full:  say m_full
        mov dx, inner
        dos 41h
        mov dx, subd
        dos 3Ah

        ; 7. delete both; nothing matches any more
        mov byte [step], '7'
        mov dx, t2
        dos 41h
        mov dx, t3
        dos 41h
        mov dx, pat
        call list
        mov dx, subd
        mov ax, 4300h
        int 21h
        jc .clean
        jmp fail
.clean: say m_clean
        mov ax, 4C00h
        int 21h

fail:   say m_fail              ; "FAIL at step n, error e" (e: DOS's, 0 = no error where one was due)
        mov dl, [step]
        mov ah, 2
        int 21h
        say m_err
        mov ax, [errc]
        call number
        say crlf
        mov ax, 4C01h
        int 21h

; list - every match of the pattern at DX: "name size", then "(n found)"
list:   mov word [count], 0
        xor cx, cx              ; plain files
        mov ah, 4Eh
        int 21h
        jc .none
.each:  inc word [count]
        mov si, 80h + 1Eh       ; the name in the DTA (PSP:0080)
.name:  lodsb
        test al, al
        jz .size
        mov dl, al
        mov ah, 2
        int 21h
        jmp .name
.size:  mov dl, ' '
        mov ah, 2
        int 21h
        mov ax, [80h + 1Ah]
        call number
        say crlf
        mov ah, 4Fh
        int 21h
        jnc .each
.none:  mov ax, [count]
        call number
        say m_found
        ret

; number - AX in decimal
number: xor cx, cx
        mov bx, 10
.div:   xor dx, dx
        div bx
        push dx
        inc cx
        test ax, ax
        jnz .div
.out:   pop dx
        add dl, '0'
        mov ah, 2
        int 21h
        loop .out
        ret

; show - AX bytes of buf in brackets, and a new line
show:   push ax
        mov dl, '['
        mov ah, 2
        int 21h
        pop cx
        jcxz .end
        mov si, buf
.ch:    lodsb
        mov dl, al
        mov ah, 2
        int 21h
        loop .ch
.end:   say m_close
        ret

t1      db 'T1.TMP', 0
t2      db 'T2.TMP', 0
t3      db 'T3.TMP', 0
pat     db 'T?.TMP', 0
subd    db 'SUBD', 0
inner   db 'SUBD\IN.TMP', 0
subpat  db 'SUBD\*.*', 0
alpha   db 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
xyz     db 'xyz'
m_made  db ' bytes written', 13, 10, '$'
m_size  db ' bytes long', 13, 10, '$'
m_pos   db ' is the position', 13, 10, '$'
m_gone  db 'T1.TMP is gone', 13, 10, '$'
m_eof   db ' bytes at the end', 13, 10, '$'
m_attr  db 'a file', 13, 10, '$'
m_dir   db 'a directory', 13, 10, '$'
m_full  db 'not empty', 13, 10, '$'
m_found db ' found', 13, 10, '$'
m_clean db 'clean', 13, 10, '$'
m_fail  db 'FAIL at step $'
m_err   db ', error $'
m_close db ']'
crlf    db 13, 10, '$'
step    db '0'
errc    dw 0
h       dw 0
count   dw 0
buf     times 64 db 0
