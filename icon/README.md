# DOS icon for Apple IIGS GS/OS Finder

This package contains standalone QuickDraw II **color Icon records**, not Macintosh `.icns` files and not a complete GS/OS `rBundle` resource fork.

## Files
- `dos_32x32.qdicon.bin` (1032 bytes): 32×32 icon record
- `dos_16x16.qdicon.bin` (264 bytes): 16×16 icon record
- `dos_32x32.png` and `dos_16x16.png`: exact pixel previews **decoded from the binary records**
- `*_zoom.png`: nearest-neighbor magnified previews
- `comparison.png`: side-by-side comparison including unscaled examples
- `build_dos_icons.py`: reproducible generator

## Structure (all little endian)
- +0 `$8000` iconType: native color icon
- +2 `width × height / 2`: size in **bytes of EACH plane**
- +4 height in pixels
- +6 width in pixels
- +8 image, packed 4 bits/pixel, two pixels per byte, high nibble left
- +8+iconSize mask, same packed layout; `$F` opaque, `$0` transparent

The design uses only palette indices `$0` (black), `$9` (red), `$E` (yellow), `$A` (green), and `$D` (blue), from the standard QuickDraw II **640-mode** 16-entry palette. Preview colors assume that standard palette. Different active GS/OS palette entries or icon conversion behavior can alter displayed colors. The blue portion is a subtle shadow; no gradients or antialiasing.

## Integration
Provide both records as big/small icon data in the Finder icon resource/bundle (typically `rBundle`, `$802B`) using your existing Monkey Island resource packaging method. Do not concatenate these two records and treat that as an `rBundle`: resource headers and bindings are separate.

The binaries have been structurally verified and round-tripped to generate PNGs, but have **not** been tested in GS/OS Finder or emulator hardware.

## References
- Apple IIGS Toolbox Reference: QuickDraw II DrawIcon record
- Apple File Type Note `$CA`, Finder Icon Files
- Apple IIGS Technical Note #63, 640-mode color table
