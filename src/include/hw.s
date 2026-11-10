*----------------------------------------------------------
* hw.s - Apple IIGS hardware, ROM and Toolbox equates shared
* by every XT/GS link. No code.
*----------------------------------------------------------
MLI       = $BF00            ; ProDOS 8 MLI entry
DEVNUM    = $BF30            ; last-used slot/drive
SYSPATH   = $0280            ; ProDOS 8: the launched system file's pathname (length byte first)
COUT      = $FDED
CROUT     = $FD8E
PRBYTE    = $FDDA
HOME      = $FC58
IDROUT    = $FE1F            ; SEC; JSR: carry clear on a IIGS
TOOLS     = $E10000          ; Toolbox dispatcher
OS_BOOT   = $E100BD          ; 0 = ProDOS 8 booted directly
GSOS      = $E100A8          ; GS/OS, inline call: JSL, dw command, adrl parameters

KBD       = $E0C000          ; keyboard data, bit 7 = strobe
KBDSTRB   = $E0C010          ; clear strobe
KEYMOD    = $E0C025          ; modifier keys
NEWVIDEO  = $E0C029          ; bit 7 SHR, bit 6 linear
BORDER    = $E0C034          ; low nibble = border colour
VBLBAR    = $E0C019          ; bit 7 = in vertical blank (ROM 3: 1 during VBL)
SPKR      = $E0C030          ; any access toggles the Apple speaker
GLU_CTL   = $E0C03C          ; sound GLU: bit 7 busy, 6 RAM (0 DOC registers),
                             ; 5 auto-increment, 3-0 master volume
GLU_DATA  = $E0C03D          ; a read returns the access before it
GLU_ADRL  = $E0C03E
GLU_ADRH  = $E0C03F
MVOLSHAD  = $E100CA          ; the Control Panel's volume (low nibble)
DOCVEC    = $E1002C          ; the firmware's sound-interrupt JML
SHR_PIX   = $E12000          ; 200 lines x 160 bytes
SHR_SCB   = $E19D00          ; 200 scan-line control bytes
SHR_PAL   = $E19E00          ; 16 palettes x 16 words

* Memory Manager attributes for a locked, fixed block at a
* fixed address in a fixed bank.
ATTR_FIXED = $C003
