`timescale 1ns / 1ps

module streamops_lane (
    input  wire [2:0] mode,
    input  wire [7:0] x,
    input  wire [7:0] imm8,
    input  wire [7:0] clamp_lo,
    input  wire [7:0] clamp_hi,
    output reg  [7:0] y
);

    localparam MODE_BYPASS    = 3'd0;
    localparam MODE_RELU      = 3'd1;
    localparam MODE_ADD_SAT   = 3'd2;
    localparam MODE_CLAMP     = 3'd3;
    localparam MODE_ABS       = 3'd4;
    localparam MODE_THRESHOLD = 3'd5;
    localparam MODE_XOR       = 3'd6;
    localparam MODE_RESERVED  = 3'd7;

    wire signed [7:0] x_s    = x;
    wire signed [7:0] imm8_s = imm8;
    wire signed [7:0] lo_s   = clamp_lo;
    wire signed [7:0] hi_s   = clamp_hi;

    wire signed [8:0] add_result = {x_s[7], x_s} + {imm8_s[7], imm8_s};
    wire signed [7:0] abs_result = (x_s == -8'sd128) ? 8'sd127 :
                        (x_s < 8'sd0)     ? -x_s    : x_s;

    always @(*) begin
        case (mode)
            MODE_BYPASS:    y = x;
            MODE_RELU:      y = (x_s < 8'sd0) ? 8'd0 : x;
            MODE_ADD_SAT:   y = (add_result > 9'sd127)  ? 8'h7F :
                                (add_result < -9'sd128) ? 8'h80 : add_result[7:0];
            MODE_CLAMP:     y = (x_s < lo_s) ? clamp_lo :
                                (x_s > hi_s) ? clamp_hi : x;
            MODE_ABS:       y = abs_result;
            MODE_THRESHOLD: y = (x_s >= imm8_s) ? 8'h7F : 8'h00;
            MODE_XOR:       y = x ^ imm8;
            default:        y = x;
        endcase
    end

endmodule
