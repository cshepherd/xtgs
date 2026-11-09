*----------------------------------------------------------
* pc.s - the emulated PC (Mode A, the .COM runner): guest
* memory map, BIOS data area fields, and the host-side
* capture/diagnostic area in bank $05.
*----------------------------------------------------------
PSP_SEG    = $1000           ; program segment prefix; the program at PSP:0100
ENV_SEG    = $0FF0           ; environment block (256 bytes at phys FF00)
BIOS_SEG   = $F000           ; stub BIOS: 256 five-byte hypercall stubs
TOP_PARA   = $A000           ; 640 KB

H_IVT      = GUEST_BASE          ; $200000
H_BDA      = GUEST_BASE+$400     ; $200400
H_ENV      = GUEST_BASE+$FF00    ; $20FF00
H_PSP      = GUEST_BASE+$10000   ; $210000
H_COM      = GUEST_BASE+$10100   ; $210100  (the loader puts the .COM here)
H_TXTBANK  = $2B0000             ; text buffer bank; cells at $8000 + row*160 + col*2
H_TXT      = $2B8000
H_BIOS     = GUEST_BASE+$F0000   ; $2F0000
STUB_LEN   = 5                   ; FE 38 lo hi CF
CALL5_OFF  = $0500               ; PSP:0005's far target: mov ah,cl / int 21h / retf

* BIOS data area (offsets from 0040:0000)
BDA_EQUIP  = $10             ; u16 equipment word
BDA_MEMKB  = $13             ; u16 conventional memory in KB
BDA_KBFLAG = $17             ; u8 shift flags
BDA_KBHEAD = $1A             ; u16 keyboard buffer head (offset in the BDA)
BDA_KBTAIL = $1C             ; u16 tail
BDA_KBBUF  = $1E             ; 16 words: $1E-$3D
BDA_KBEND  = $3E
BDA_VMODE  = $49             ; u8 video mode
BDA_COLS   = $4A             ; u16 columns
BDA_PGSIZE = $4C             ; u16 page size in bytes
BDA_PGOFF  = $4E             ; u16 page offset
BDA_CURPOS = $50             ; 8 x u16: col | row<<8
BDA_CURSHP = $60             ; u16 cursor shape (start<<8 | end)
BDA_PAGE   = $62             ; u8 active page
BDA_CRTC   = $63             ; u16 CRTC base port
BDA_TICKS  = $6C             ; u32 timer ticks since midnight
BDA_MIDNT  = $70             ; u8 midnight flag
BDA_ROWS   = $84             ; u8 rows - 1
BDA_CHARHT = $85             ; u16 character height

* Host-side capture and diagnostics (bank $05, after the harness header)
CAP_LEN    = RES_BASE+$800   ; u16 bytes captured
DIAG_UNH   = RES_BASE+$802   ; u16 first unhandled: vector | AH<<8 ($FFFF none)
DIAG_UNHN  = RES_BASE+$804   ; u16 unhandled calls
DIAG_LAST  = RES_BASE+$806   ; u16 last INT 21h function seen (AH)
CAP_BUF    = RES_BASE+$1000
CAP_MAX    = $7000
