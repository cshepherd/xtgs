*----------------------------------------------------------
* pc.s - the emulated PC (Mode A, the .COM runner): guest
* memory map, BIOS data area fields, and the host-side
* capture/diagnostic area in bank $05.
*----------------------------------------------------------
PSP_SEG    = $1000           ; program segment prefix; the program at PSP:0100
ENV_SEG    = $0FE0           ; environment block (256 bytes at phys FE00)
BIOS_SEG   = $F000           ; stub BIOS: 256 five-byte hypercall stubs
TOP_PARA   = $A000           ; 640 KB

H_IVT      = GUEST_BASE          ; $200000
H_BDA      = GUEST_BASE+$400     ; $200400
H_ENV      = GUEST_BASE+$FE00    ; $20FE00
H_MCB      = GUEST_BASE+$FFF0    ; the one memory control block, below the PSP
H_PSP      = GUEST_BASE+$10000   ; $210000
H_COM      = GUEST_BASE+$10100   ; $210100  (the loader puts the .COM here)
H_TXTBANK  = $2B0000             ; text buffer bank; cells at $8000 + row*160 + col*2
H_TXT      = $2B8000
H_BIOS     = GUEST_BASE+$F0000   ; $2F0000
STUB_LEN   = 5                   ; FE 38 lo hi CF
CALL5_OFF  = $0500               ; PSP:0005's far target: mov ah,cl / int 21h / retf
DOSDATA_SEG = $F800              ; DOS's visible data: the fake DPB and list of lists
H_DOSDATA  = GUEST_BASE+$F8000
DPB_OFF    = $0040               ; DPB at F800:0040
LOL_OFF    = $0082               ; list of lists at F800:0082 (first MCB word at -2)
MCB_FIRST  = $0FFF               ; our one MCB, just below the PSP
VID_DIRTY  = RES_BASE+$900       ; 64 bytes: a 256-byte page of the B800 bank was
                                 ; written (core hook). Text uses pages 0-15 (4 KB);
                                 ; CGA graphics use 0-63 (the 16 KB framebuffer).

* Mode B (disk boot): the disk image is loaded into host banks from
* DISK_BASE; INT 13h serves sectors from there. A 1.44 MB floppy is 23
* banks ($50-$66).
DISK_BASE  = $500000             ; host address of the image's sector 0
DISK_BANK  = $50
BOOT_LIN   = $7C00               ; the boot sector loads to 0000:7C00
DISK_SPT   = 18                  ; 1.44 MB floppy geometry
DISK_HEADS = 2
DISK_CYLS  = 80
MB_DISKLEN = RES_BASE+$808       ; u32 bytes of the image loaded
MB_INT13N  = RES_BASE+$80C       ; u16 INT 13h calls served (diagnostic)
MB_BOOTTRC = RES_BASE+$80E       ; u16 boot trace / stage

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
DIAG_FNMAP = RES_BASE+$810   ; 16 bytes: bit AH set for each unhandled/failed INT 21h function
DIAG_INTMAP = RES_BASE+$820  ; 32 bytes: bit n set for each unhandled INT n
* Hardware keyboard: a scancode ring the core serves at port 0x60 and the
* slot check delivers as IRQ1/INT 09h. Shared by CORE (port read, IRQ) and
* SVC (kb_poll enqueues make+break). 32 entries, head==tail = empty.
KBD_QHEAD  = RES_BASE+$844   ; u16 read index (0..31)
KBD_QTAIL  = RES_BASE+$846   ; u16 write index (0..31)
KBD_QBUF   = RES_BASE+$850   ; 32 scancode bytes
KBD_QMASK  = $001F
CGA_MODEREQ = RES_BASE+$870  ; last value written to CGA mode-control port 0x3D8
CGA_MODECHG = RES_BASE+$872  ; nonzero: that write is pending (svc_vbl applies it)
PIT_CTR    = RES_BASE+$874   ; free-running state for 8253 PIT reads (port 0x40/0x42)
SPK_PORT   = RES_BASE+$876   ; the 8255's port B (61h) as last written
DOC_IRQS   = RES_BASE+$878   ; u16 DOC timer interrupts taken (diagnostic)
DOC_DROPS  = RES_BASE+$87A   ; u16 of those, dropped with vTICK at TICK_MAX
TICK_OFF   = $0510           ; F000:0510, INT 08h: hypercall 8 / int 1Ch / iret
CAP_BUF    = RES_BASE+$1000
CAP_MAX    = $7000
