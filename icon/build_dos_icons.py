#!/usr/bin/env python3
"""Generate authentic 4bpp Apple IIgs QuickDraw II icon records (image + mask)."""
from PIL import Image, ImageDraw
from pathlib import Path
import struct, zipfile

OUT=Path('/mnt/data/dos_gsos_icons'); OUT.mkdir(exist_ok=True)
# Apple IIGS standard QuickDraw II 640-mode palette, TN #63.
RGB=[(0,0,0),(255,0,0),(0,255,0),(255,255,255),
     (0,0,0),(0,0,255),(255,255,0),(255,255,255),
     (0,0,0),(255,0,0),(0,255,0),(255,255,255),
     (0,0,0),(0,0,255),(255,255,0),(255,255,255)]
# indices: 0 black, 9 red, E yellow, A green, D blue
FONT_7X9={
'D':['1111100','1100110','1100011','1100011','1100011','1100011','1100011','1100110','1111100'],
'O':['0111110','1100011','1100011','1100011','1100011','1100011','1100011','1100011','0111110'],
'S':['0111111','1100000','1100000','0111100','0000110','0000011','0000011','1100011','1111110']}
FONT_3X5={
'D':['110','101','101','101','110'],
'O':['111','101','101','101','111'],
'S':['111','100','111','001','111']}

def glyph_pixels(char, small):
    glyph=FONT_3X5[char] if small else FONT_7X9[char]
    sy=1 if small else 2
    return [(x,y*sy+dy) for y,line in enumerate(glyph) for x,p in enumerate(line) if p=='1' for dy in range(sy)]

def make_icon(size):
    p=Image.new('P',(size,size),0)
    transparent=Image.new('1',(size,size),0)
    colors=[9,14,10]
    small=size==16
    positions=[(2,5),(7,5),(12,5)] if small else [(3,6),(12,6),(21,6)]
    shapes=[]
    for (x,y),letter,color in zip(positions,'DOS',colors):
        shapes.append(({(x+dx,y+dy) for dx,dy in glyph_pixels(letter,small)},color))
    # Silhouette outline black. Transparent outside silhouette.
    filled=set().union(*(s for s,c in shapes))
    offsets=[(dx,dy) for dx in (-1,0,1) for dy in (-1,0,1)]
    outline={(x+dx,y+dy) for x,y in filled for dx,dy in offsets if 0<=x+dx<size and 0<=y+dy<size}
    px=p.load(); mk=transparent.load()
    for x,y in outline: px[x,y]=0; mk[x,y]=1
    # Offset blue shadow: behind glyphs; keep minimal for small Finder view.
    shadow={(x+1,y+2) for x,y in outline if 0<=x+1<size and 0<=y+2<size}
    for x,y in shadow-outline: px[x,y]=13; mk[x,y]=1
    for shape,color in shapes:
        for x,y in shape:
            px[x,y]=color; mk[x,y]=1
    return p,transparent

def pack_plane(pixels,width,height):
    vals=[]
    for y in range(height):
        for x in range(0,width,2):
            vals.append(((pixels.getpixel((x,y))&15)<<4)|(pixels.getpixel((x+1,y))&15))
    return bytes(vals)

for size in (16,32):
    art,opacity=make_icon(size)
    mask=Image.new('P',(size,size),0)
    for y in range(size):
        for x in range(size): mask.putpixel((x,y),15 if opacity.getpixel((x,y)) else 0)
    n=size*size//2
    # iconType $8000 = color, iconSize bytes per plane, height, width
    binary=struct.pack('<HHHH',0x8000,n,size,size)+pack_plane(art,size,size)+pack_plane(mask,size,size)
    assert len(binary)==8+2*n
    (OUT/f'dos_{size}x{size}.qdicon.bin').write_bytes(binary)
    # Re-decode binary independently for preview and verification.
    ty,plane,hei,wid=struct.unpack_from('<HHHH',binary)
    assert (ty,plane,hei,wid)==(0x8000,n,size,size)
    raw=binary[8:8+n]; masks=binary[8+n:]
    preview=Image.new('RGBA',(size,size))
    for y in range(size):
        for x in range(size):
            idx=y*(size//2)+(x//2)
            c=(raw[idx]>>4) if x%2==0 else (raw[idx]&15)
            m=(masks[idx]>>4) if x%2==0 else (masks[idx]&15)
            preview.putpixel((x,y),(*RGB[c],255 if m else 0))
    preview.save(OUT/f'dos_{size}x{size}.png')
    preview.resize((size*12,size*12),resample=Image.Resampling.NEAREST).save(OUT/f'dos_{size}x{size}_zoom.png')
    # strict round trip
    assert all((preview.getpixel((x,y))[3]>0)==bool(opacity.getpixel((x,y))) for y in range(size) for x in range(size))

# composite on gray Finder desktop-style backdrop, at actual size as well as pixel zoom
contact=Image.new('RGB',(520,250),(212,212,212)); d=ImageDraw.Draw(contact)
for s,x in [(16,72),(32,290)]:
    ico=Image.open(OUT/f'dos_{s}x{s}.png').convert('RGBA')
    zoom=ico.resize((s*6,s*6),Image.Resampling.NEAREST)
    contact.paste(zoom,(x,30),zoom)
    contact.paste(ico,(x,212),ico)
    d.text((x,8),f'{s}x{s}',fill='black')
contact.save(OUT/'comparison.png')
readme='''# DOS icon for Apple IIGS GS/OS Finder

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
'''
(OUT/'README.md').write_text(readme)
(OUT/'build_dos_icons.py').write_bytes(Path(__file__).read_bytes())
zip_path=Path('/mnt/data/dos_gsos_icon_kit.zip')
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as z:
    for f in OUT.iterdir(): z.write(f,'dos_gsos_icons/'+f.name)
print(zip_path, zip_path.stat().st_size)
for p in sorted(OUT.glob('*.bin')): print(p, p.stat().st_size)
