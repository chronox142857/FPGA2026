# Original project UI font

`font5x7.json` is extracted from the original `symbols`/`glyphs` arrays in
`E:\FPGAproject\FPGA2026\firmware\src\ui.c`. Each glyph is seven rows of five
bits, with the highest bit on the left. This is the project-authored font,
independent of the STM32 8x16/Chinese font library.

`make_text_reference.py` builds the expected framebuffer using these C font
rows. The Verilog SPI LCD model compares every reconstructed pixel with it.
