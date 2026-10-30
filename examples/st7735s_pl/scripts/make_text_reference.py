"""Independent framebuffer from the original C UI font, for SPI-model checking."""
from pathlib import Path
import json
import struct
import zlib

root=Path(__file__).resolve().parents[1]
font=json.loads((root/'reference/ui_font/font5x7.json').read_text())
labels=['LOGIC ANALYZER','SCREEN READY','FPGA ZYNQ7010','UART I2C SPI',
        'CH 0 1 2 3 4 5 6 7','DISPLAY TEST','CAPTURE OFF','0123456789ABCDEF']
colors=[0x07ff,0x07e0,0xffff,0xffe0,0x07ff,0xffff,0x8410,0xffff]
pixels=[0]*16384
for line,(label,color) in enumerate(zip(labels,colors)):
    assert len(label)<=20
    for char,ch in enumerate(label):
        glyph=font.get(ch,[0]*7)
        for y,row in enumerate(glyph):
            for x in range(5):
                if row & (1<<(4-x)):
                    pixels[(line*16+y)*128+4+char*6+x]=color
build=root/'build';(build/'sim').mkdir(parents=True,exist_ok=True)
(build/'sim/text_expected.hex').write_text(''.join(f'{p:04x}\n' for p in pixels),encoding='ascii')
# Standard PNG encoder; no external image library needed for this test preview.
def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
scan=bytearray()
for y in range(384):
    scan.append(0)
    for x in range(384):
        p=pixels[(y//3)*128+x//3]
        scan.extend((((p>>11)&31)*255//31,((p>>5)&63)*255//63,(p&31)*255//31))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',384,384,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b'')
(build/'text_preview.png').write_bytes(png)
print('Text reference: 16384 pixels;',sum(p!=0 for p in pixels),'foreground pixels')
