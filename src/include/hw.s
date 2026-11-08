*----------------------------------------------------------
* hw.s - Apple IIGS hardware, ROM and Toolbox equates shared
* by every XT/GS link. No code.
*----------------------------------------------------------
MLI       = $BF00            ; ProDOS 8 MLI entry
DEVNUM    = $BF30            ; last-used slot/drive
COUT      = $FDED
CROUT     = $FD8E
PRBYTE    = $FDDA
HOME      = $FC58
IDROUT    = $FE1F            ; SEC; JSR: carry clear on a IIGS
TOOLS     = $E10000          ; Toolbox dispatcher
OS_BOOT   = $E100BD          ; 0 = ProDOS 8 booted directly

KBD       = $E0C000          ; keyboard data, bit 7 = strobe
KBDSTRB   = $E0C010          ; clear strobe
KEYMOD    = $E0C025          ; modifier keys
NEWVIDEO  = $E0C029          ; bit 7 SHR, bit 6 linear
BORDER    = $E0C034          ; low nibble = border colour
VBLBAR    = $E0C019          ; bit 7 = in vertical blank (ROM 3: 1 during VBL)
SHR_PIX   = $E12000          ; 200 lines x 160 bytes
SHR_SCB   = $E19D00          ; 200 scan-line control bytes
SHR_PAL   = $E19E00          ; 16 palettes x 16 words

* Memory Manager attributes for a locked, fixed block at a
* fixed address in a fixed bank.
ATTR_FIXED = $C003
