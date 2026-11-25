*----------------------------------------------------------
* mailbox.s - the front end's page in bank $00 (MBX_PAGE in
* layout.s): what the loader, the core, the services bank
* and the host-side judges exchange.
*
*   +$00  the front end's own (XTGS.SYSTEM: JMP start)
*   +$04  MB_FILECALL: JSL here, native mode, any M/X, to
*         make the ProDOS 8 MLI call MB_MLI_CMD with the
*         parameter list at MB_MLI_PARMS. Returns A = the
*         error code (0 = ok), also in MB_MLI_RES; D, DBR
*         and P are preserved. The pointers in the list are
*         bank-$00 addresses (PATH, XFER, IOB in layout.s).
*   +$08  u16 XTGS.SYSTEM's file length (tools/gen_reloc.py)
*   +$10  the mailbox, below
*
* With the default layout the page is the first of the
* XTGS.SYSTEM image ($2000). CORE and SVC reach it through
* these equates, so it is wherever MB_LAYOUT says; the
* judges read the loader's listing (tools/symbols.py),
* whose mb_ labels XTGS.SYSTEM asserts against these.
*----------------------------------------------------------
MB_BASE     = MBX_PAGE*$100
MB_FILECALL = MB_BASE+$04
MB_SELFLEN  = MB_BASE+$08
MB_STAGE    = MB_BASE+$10    ; u16 loader/core stage (diagnosis)
MB_MAGIC    = MB_BASE+$12    ; u16 $5A5A once everything is final
MB_EXIT     = MB_BASE+$14    ; u16 core exit code (A at RTL)
MB_ERR      = MB_BASE+$16    ; u16 first tool/MLI error
MB_OSBOOT   = MB_BASE+$18    ; u16 byte at $E1:00BD
MB_MASTER   = MB_BASE+$1A    ; u16 master user ID
MB_MMID     = MB_BASE+$1C    ; u16 ID returned by MMStartUp
MB_DOWNERR  = MB_BASE+$1E    ; u16 first error during shutdown
MB_DONE     = MB_BASE+$20    ; u16 $A5A5 once the core has returned
MB_FILELEN  = MB_BASE+$22    ; u32 bytes of the data file loaded (VEC/COM)
MB_SP       = MB_BASE+$26    ; u16 loader stack pointer while the core runs
MB_PROBE_ERRS = MB_BASE+$28  ; u16 memory-probe mismatches
MB_PROBE_FIRST = MB_BASE+$2A ; u32 first mismatching host address
MB_RUNIDX   = MB_BASE+$2E    ; u16 vector index in progress (harness)
MB_CMD      = MB_BASE+$30    ; 32 bytes: Pascal string from XTGS.CMD
MB_DBG_OWNER = MB_BASE+$50   ; u16 owner ID of the block that made a fixed NewHandle fail
MB_DBG_ADDR = MB_BASE+$52    ; u32 its address
MB_DBG_SIZE = MB_BASE+$56    ; u32 its size
MB_MLI_CMD  = MB_BASE+$5A    ; u16 file call: the ProDOS 8 MLI command byte
MB_MLI_RES  = MB_BASE+$5C    ; u16 its result (error code, 0 = ok)
MB_MLI_PARMS = MB_BASE+$5E   ; 32 bytes: its parameter list
MB_ICOUNT   = MB_BASE+$7E    ; u32 slots run, times SLOT_N (bench)
MB_LAYOUT   = MB_BASE+$82    ; RG_COUNT words: the bank of each region, the page of each bank-$00 area (0 = not claimed)
MB_LAYALT   = RG_COUNT*2+MB_LAYOUT ; u16 nonzero: the '+' test layout was asked for
MB_ARG      = MB_LAYALT+2    ; u32 a document XT/GS was opened with (src/svc/ghost.s): where its pathname is,
                             ;     "/VOL/DIR/NAME" (Pascal, in 256 bytes of the front end's), then its keys
MB_ARGN     = MB_ARG+4       ; u16 0 none, 1 the pathname, 2 the keys to type, $8000 + why it was refused
MB_ARGI     = MB_ARGN+2      ; u16 the next key to type, from 1
MB_END      = MB_ARGI+2

* The regions' bases come from layout.s (PUT before this file).
* Bench program destination: guest 0000:0100.
BENCH_BASE  = GUEST_BASE+$100
* The .COM program: guest PSP_SEG:0100 (pc.s's H_COM).
COM_BASE    = GUEST_BASE+$10100
TRACE_BASE  = RES_BASE+$4000 ; instruction trace ring (8 bytes an entry)
TRACE_LEN   = $4000          ; 2048 entries
