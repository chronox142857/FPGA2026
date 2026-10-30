// Original 5x7 uppercase font from FPGA2026 firmware/src/ui.c.
// Each glyph is seven rows, MSB is the leftmost pixel.
module st7735s_font5x7(input wire [7:0] character, input wire [2:0] row, column, output wire ink);
    reg [34:0] bitmap;
    always @* begin
        case(character)
            8'd48: bitmap=35'h3a33ae62e; // 0
            8'd49: bitmap=35'h11842108e; // 1
            8'd50: bitmap=35'h3a211111f; // 2
            8'd51: bitmap=35'h78217043e; // 3
            8'd52: bitmap=35'h08ca97c42; // 4
            8'd53: bitmap=35'h7e10f043e; // 5
            8'd54: bitmap=35'h3a10f462e; // 6
            8'd55: bitmap=35'h7c2222108; // 7
            8'd56: bitmap=35'h3a317462e; // 8
            8'd57: bitmap=35'h3a317842e; // 9
            8'd65: bitmap=35'h3a31fc631; // A
            8'd66: bitmap=35'h7a31f463e; // B
            8'd67: bitmap=35'h3e108420f; // C
            8'd68: bitmap=35'h7a318c63e; // D
            8'd69: bitmap=35'h7e10f421f; // E
            8'd70: bitmap=35'h7e10f4210; // F
            8'd71: bitmap=35'h3e109c62f; // G
            8'd72: bitmap=35'h4631fc631; // H
            8'd73: bitmap=35'h38842108e; // I
            8'd74: bitmap=35'h1c4210a4c; // J
            8'd75: bitmap=35'h4654c5251; // K
            8'd76: bitmap=35'h42108421f; // L
            8'd77: bitmap=35'h4775ac631; // M
            8'd78: bitmap=35'h4739ace71; // N
            8'd79: bitmap=35'h3a318c62e; // O
            8'd80: bitmap=35'h7a31f4210; // P
            8'd81: bitmap=35'h3a318d64d; // Q
            8'd82: bitmap=35'h7a31f5251; // R
            8'd83: bitmap=35'h3e107043e; // S
            8'd84: bitmap=35'h7c8421084; // T
            8'd85: bitmap=35'h46318c62e; // U
            8'd86: bitmap=35'h46318c544; // V
            8'd87: bitmap=35'h4631ad771; // W
            8'd88: bitmap=35'h462a22a31; // X
            8'd89: bitmap=35'h462a21084; // Y
            8'd90: bitmap=35'h7c222221f; // Z
            8'd45: bitmap=35'h0000f8000; // -
            8'd46: bitmap=35'h0000000c6; // .
            8'd58: bitmap=35'h00c6018c0; // :
            8'd47: bitmap=35'h044222110; // /
            8'd37: bitmap=35'h674222173; // %
            8'd63: bitmap=35'h3a2111004; // ?
            8'd43: bitmap=35'h0084f9080; // +
            8'd61: bitmap=35'h001f07c00; // =
            8'd60: bitmap=35'h088882082; // <
            8'd62: bitmap=35'h208208888; // >
            8'd95: bitmap=35'h00000001f; // _
            default: bitmap=0;
        endcase
    end
    assign ink=(row<7 && column<5) ? bitmap[34-row*5-column] : 1'b0;
endmodule
