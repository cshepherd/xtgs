*----------------------------------------------------------
* mailbox.s - the loader's mailbox: fixed bank-$00 addresses
* inside the XTGS.SYSTEM image, read by the core, the
* services bank and the host-side judge (tools/symbols.py
* reads the loader listing; these equates are the same
* numbers for the other links). XTGS.SYSTEM asserts each
* label against its equate with ERR lines.
*----------------------------------------------------------
MB_STAGE    = $2010          ; u16 loader/core stage (diagnosis)
MB_MAGIC    = $2012          ; u16 $5A5A once everything is final
MB_EXIT     = $2014          ; u16 core exit code (A at RTL)
MB_ERR      = $2016          ; u16 first tool/MLI error
MB_OSBOOT   = $2018          ; u16 byte at $E1:00BD
MB_MASTER   = $201A          ; u16 master user ID
MB_MMID     = $201C          ; u16 ID returned by MMStartUp
MB_DOWNERR  = $201E          ; u16 first error during shutdown
MB_DONE     = $2020          ; u16 $A5A5 once the core has returned
MB_FILELEN  = $2022          ; u32 bytes of the data file loaded (VEC/COM)
MB_SP       = $2026          ; u16 loader stack pointer while the core runs
MB_PROBE_ERRS = $2028        ; u16 memory-probe mismatches
MB_PROBE_FIRST = $202A        ; u32 first mismatching host address
MB_RUNIDX   = $202E          ; u16 vector index in progress (harness)
MB_CMD      = $2030          ; 32 bytes: Pascal string from XTGS.CMD
MB_DBG_OWNER = $2050          ; u16 owner ID of the block that made a fixed NewHandle fail
MB_DBG_ADDR = $2052          ; u32 its address
MB_DBG_SIZE = $2056          ; u32 its size
MB_MLI_CMD  = $205A          ; u16 MLI command byte for the glue at $2004
MB_MLI_RES  = $205C          ; u16 its result (error code, 0 = ok)
MB_MLI_PARMS = $205E          ; 32 bytes: its parameter list
MB_ICOUNT   = $207E          ; u32 instructions retired (bench; in SLOT_N units)
MB_END      = $2082

* Data file destination (VEC): bank-aligned, grows upward.
DATA_BASE   = $300000
* Bench program destination: guest 0000:0100.
BENCH_BASE  = $200100
* Guest physical memory: 1 MiB, 1 MiB-aligned.
GUEST_BASE  = $200000
GUEST_BANK  = $20
CORE_BASE   = $030000
SVC_BASE    = $040000
RES_BASE    = $050000        ; harness results / trace ring
TRACE_BASE  = $054000        ; instruction trace ring (8 bytes an entry)
TRACE_LEN   = $4000          ; 2048 entries
