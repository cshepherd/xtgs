*----------------------------------------------------------
* layout.s - the places XT/GS is ASSEMBLED for: the bank of
* each region, and the page of each area CORE and SVC use
* in bank $00. Every other bank number and bank-$00 address
* in the three links derives from these equates, and
* nothing else in the tree may spell one out.
*
* They are first choices, not promises. The front end (the
* ProDOS 8 loader, src/sys/xtgs.s) decides where each one
* really is, records it in MB_LAYOUT, and adds (actual -
* assembled) to every byte of CORE and SVC that holds one:
* a bank byte for a region, the high byte of a bank-$00
* address for a page. tools/gen_reloc.py finds those bytes
* by assembling each image again with these lines moved,
* and appends the list to the image (docs/relocation.md).
*
* The build rewrites the "NAME_BANK = $xx" and "NAME_PAGE =
* $xx" lines below, so keep that exact shape: one a line, a
* hex byte. The guest's megabyte must start at a multiple
* of $10 (the 20-bit wrap is AND #$000F / ORA #GUEST_BANK).
* The bank-$00 areas are whole pages: a page number is the
* high byte of every address in its first page.
*
* RG_* is the index of a region or a page area: into the
* loader's tables, into MB_LAYOUT (a word each: the bank or
* the page) and in the relocation lists. The banks come
* first (RG_BANKS of them), then the pages.
*----------------------------------------------------------
CORE_BANK   = $03            ; the CPU (CORE), one bank
SVC_BANK    = $04            ; the services (SVC), one bank
RES_BANK    = $05            ; results, trace ring, queues, capture: one bank
JIT_BANK    = $06            ; the translator: its image, a bank of the code it makes, a bank of map (docs/jit.md; K: the first M6's cache)
GUEST_BANK  = $20            ; the guest's 1 MiB: 16 banks
DATA_BANK   = $30            ; the vector file (V only), sized by the file
DISK_BANK   = $50            ; the Mode B disk image (D only): 23 banks

* Bank $00. ZP is the direct page while CORE and SVC run (guest.s);
* MBX is the front end's page (mailbox.s): its file-call entry and the
* mailbox; PATH, XFER and IOB are what the ProDOS 8 MLI needs in bank
* $00 for the DOS file calls (src/svc/files.s).
ZP_PAGE     = $10            ; guest CPU state, the direct page: 1 page
MBX_PAGE    = $20            ; file-call entry and mailbox: 1 page
PATH_PAGE   = $0C            ; two pathnames and the volume prefix: 1 page
XFER_PAGE   = $40            ; file transfer buffer: 8 KB
IOB_PAGE    = $60            ; ProDOS 8 I/O buffers, 1 KB an open file: 8 KB

* The pages of the loader's '+' test layout (it finds the banks by
* asking the Memory Manager). tools/layout.py reads these too. The two
* 8 KB areas change places.
ZP_ALTPG    = $11
MBX_ALTPG   = $12
PATH_ALTPG  = $13
XFER_ALTPG  = $60
IOB_ALTPG   = $40

RG_CORE     = 0
RG_SVC      = 1
RG_RES      = 2
RG_JIT      = 3
RG_GUEST    = 4
RG_DATA     = 5
RG_DISK     = 6
RG_BANKS    = 7              ; the regions above; the pages follow
RG_ZP       = 7
RG_MBX      = 8
RG_PATH     = 9
RG_XFER     = 10
RG_IOB      = 11
RG_COUNT    = 12

DISK_BANKS  = 23             ; 1.44 MB = 2880 sectors = 22.5 banks
RELOC_MAGIC = $5258          ; "XR": the last word of a relocatable image

CORE_BASE   = CORE_BANK*$10000
JIT_BASE    = JIT_BANK*$10000        ; the translator's image (src/jit): +0 a PC starts
JIT_RT      = JIT_BASE+$10000        ; its run-time routines (entries at +0, +3, +6, +9) and the code it makes
JIT_MAP     = JIT_BASE+$20000        ; a word for a guest IP (jit_bk in the core)
JIT_RT2     = JIT_BASE+$30000        ; the same routines again, and the code made when JIT_RT's bank is full
SVC_BASE    = SVC_BANK*$10000
RES_BASE    = RES_BANK*$10000        ; harness results / trace ring
GUEST_BASE  = GUEST_BANK*$10000      ; guest physical memory: 1 MiB, 1 MiB-aligned
DATA_BASE   = DATA_BANK*$10000       ; data file destination (VEC): grows upward
DISK_BASE   = DISK_BANK*$10000       ; host address of the disk image's sector 0
