*----------------------------------------------------------
* guest.s - the emulated 8086's state, in the direct page at
* D = $1000 (bank $00). Registers are in the 8086's own
* encoding order so ModR/M fields index them: AX CX DX BX
* SP BP SI DI, and ES CS SS DS. $00-$7F is the core's,
* $80-$FF the services bank's scratch.
*----------------------------------------------------------
GUEST_DP   = $1000

           DUM 0
rAX        DS 2              ; $00  AL, AH
rCX        DS 2              ; $02
rDX        DS 2              ; $04
rBX        DS 2              ; $06
rSP        DS 2              ; $08
rBP        DS 2              ; $0A
rSI        DS 2              ; $0C
rDI        DS 2              ; $0E
rES        DS 2              ; $10
rCS        DS 2              ; $12
rSS        DS 2              ; $14
rDS        DS 2              ; $16
rIP        DS 2              ; $18  spilled copy; Y holds IP in the loop
rFL        DS 2              ; $1A  FLAGS
bES        DS 4              ; $1C  host base: lo16, then $00bb
bCS        DS 4              ; $20
bSS        DS 4              ; $24
bDS        DS 4              ; $28
vEA        DS 2              ; $2C  effective offset
pEA        DS 4              ; $2E  host pointer of the r/m operand (lo16, $00bb)
vMODRM     DS 2              ; $32  ModR/M byte (word store)
vSEGOVR    DS 2              ; $34  0, or DP offset of the override base
vREP       DS 2              ; $36  0, $F2, $F3
vREGOFF    DS 2              ; $38  DP offset of the reg operand
vNEXT      DS 2              ; $3A  where a handler goes when it retires
tmp0       DS 2              ; $3C
tmp1       DS 2              ; $3E
tmp2       DS 2              ; $40
tmp3       DS 2              ; $42
vINTPEND   DS 1              ; $44  pending hardware interrupt vector + 1, 0 none
vHALT      DS 1              ; $45
vSLOT      DS 2              ; $46  instructions until the next slot check
vICOUNT    DS 4              ; $48  retired instructions
vIPSTART   DS 2              ; $4C  IP of the instruction's first prefix/opcode
vSTEP      DS 2              ; $4E  harness: nonzero = retire returns to caller
pSRC       DS 4              ; $50  string source pointer
pDST       DS 4              ; $54  string destination pointer
vCOUNT     DS 2              ; $58
vBOUNCE    DS 2              ; $5A  word operand split across a segment wrap
pSPLIT     DS 4              ; $5C  its second byte's host pointer
tmp4       DS 2              ; $60
tmp5       DS 2              ; $62
tmp6       DS 2              ; $64
tmp7       DS 2              ; $66
vOF        DS 2              ; $68  OF as $0080 (set) or $0000; FLAGS bit 11 is assembled on demand
vNEXT2     DS 2              ; $6A  vNEXT saved by the split path
pSTK       DS 4              ; $6C  stack pointer (host)
pTMP       DS 4              ; $70  split path's second byte
vBAD       DS 2              ; $74  unimplemented opcodes retired (harness)
vIDX       DS 2              ; $76  harness: vector index
vRECLEN    DS 2              ; $78  harness: record length
vXRAMOFF   DS 2              ; $7A  harness: offset of the expected-RAM list
vNRUN      DS 2              ; $7C  harness: vectors run
vNPASS     DS 2              ; $7E  harness: vectors passed
sv0        DS 2              ; $80  services scratch
sv1        DS 2
sv2        DS 2
sv3        DS 2
sv4        DS 2
sv5        DS 2
sv6        DS 2
sv7        DS 2
pCELL      DS 4              ; $90  SHR cell pointer
pTXT       DS 4              ; $94  text buffer pointer
pGST       DS 4              ; $98  services: a guest pointer
sv8        DS 2              ; $9C
sv9        DS 2              ; $9E
vCF        DS 2              ; $A0  shift/rotate carry (0/1)
vFAIL      DS 2              ; $A2  harness: mismatches in this vector
vTMP       DS 2              ; $A4
pSTK2      DS 4              ; $A6  stack split path's second byte
vHALTVEC   DS 2              ; $AA  where HLT goes: step_done (harness) or run_done
pVEC       DS 4              ; $AC  harness: the vector record
vEASEG     DS 2              ; $B0  DP offset of the segment base the last EA used
vEXIT      DS 2              ; $B2  program exit code (hypercall terminate)
vVBL       DS 2              ; $B4  last sampled VBL state ($0080 / 0)
vPCMODE    DS 2              ; $B6  nonzero: the slot runs the PC's VBL work
pDTA       DS 4              ; $B8  services: host pointer to the DTA
pARG       DS 4              ; $BC  services: a second guest pointer (parse source, PSP copy)
pIMG       DS 4              ; $C0  Mode B: host pointer into the disk image
vTRACE     DS 2              ; $C4  nonzero: log each retired instruction to the ring
vTRPTR     DS 2              ; $C6  ring write index (bytes, wraps at TRACE_LEN)
pEMIT      DS 4              ; $C8  M6 JIT: emit pointer into the code cache ($06:off)
jEntry     DS 2              ; $CC  native offset where the block being built started
pMAP       DS 4              ; $CE  pointer to the current block-map slot
jLIN       DS 4              ; $D2  guest linear IP (CS*16+IP, 20 bits)
jtmp       DS 2              ; $D6
jtmp2      DS 2              ; $D8
jPrevFlag  DS 2              ; $DA  JIT: DP offset the last emitted flag-op wrote (0 none)
pENTER     DS 4              ; $DC  JIT: pointer used by jml [] to enter a block
gSRC       DS 4              ; $E0  CGA blit: source pointer (B800 field)
gDST       DS 4              ; $E4  CGA blit: dest pointer (SHR line)
gE         DS 2              ; $E8  CGA blit: fieldbase / scratch
gO         DS 2              ; $EA  CGA blit: scratch
gL         DS 2              ; $EC  CGA blit: scratch
gPG        DS 2              ; $EE  CGA flush: dirty page index 0..63
gPAR       DS 2              ; $F0  CGA flush: field parity 0/1
gROW       DS 2              ; $F2  CGA flush: current row-in-field
gR1        DS 2              ; $F4  CGA flush: last row-in-field for this page
           DEND

* JMP (abs) takes a bank-$00 address: the retire vector's.
* (A numeric equate: Merlin32 evaluates equates before labels.)
NEXTVEC    = $103A
HALTVEC    = $10AA
SLOT_N     = 16              ; instructions between slot checks (VBL polling)

* FLAGS bits
F_CF       = $0001
F_PF       = $0004
F_AF       = $0010
F_ZF       = $0040
F_SF       = $0080
F_TF       = $0100
F_IF       = $0200
F_DF       = $0400
F_OF       = $0800
F_FIXED    = $F002           ; read as 1 on an 8086/8088
