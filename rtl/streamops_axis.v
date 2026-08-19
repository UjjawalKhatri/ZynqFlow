`timescale 1ns / 1ps

module streamops_axis #(
    parameter DATA_W = 64
)(
    input  wire                    aclk,
    input  wire                    aresetn,

    // AXI4-Stream slave (input)
    input  wire [DATA_W-1:0]      s_axis_tdata,
    input  wire [DATA_W/8-1:0]    s_axis_tkeep,
    input  wire                    s_axis_tvalid,
    output wire                    s_axis_tready,
    input  wire                    s_axis_tlast,

    // AXI4-Stream master (output)
    output wire [DATA_W-1:0]      m_axis_tdata,
    output wire [DATA_W/8-1:0]    m_axis_tkeep,
    output wire                    m_axis_tvalid,
    input  wire                    m_axis_tready,
    output wire                    m_axis_tlast,

    // Control signals
    input  wire                    enable,
    input  wire [2:0]             mode,
    input  wire [7:0]             imm8,
    input  wire [7:0]             clamp_lo,
    input  wire [7:0]             clamp_hi,
    input  wire                    cnt_clear,

    // Status counters
    output reg  [31:0]            input_beats,
    output reg  [31:0]            output_beats,
    output reg  [31:0]            stall_cycles,
    output reg  [31:0]            frame_count,
    output reg  [31:0]            active_cycles
);

    localparam N_LANES = DATA_W / 8;
    wire [DATA_W-1:0] transformed_data;

    genvar i;
    generate
        for (i = 0; i < N_LANES; i = i + 1) begin : lane_gen
            streamops_lane u_lane (
                .mode     (mode),
                .x        (s_axis_tdata[i*8 +: 8]),
                .imm8     (imm8),
                .clamp_lo (clamp_lo),
                .clamp_hi (clamp_hi),
                .y        (transformed_data[i*8 +: 8])
            );
        end
    endgenerate

    reg [DATA_W-1:0]  out_tdata;
    reg [N_LANES-1:0] out_tkeep;
    reg               out_tlast;
    reg               out_valid;

    wire can_accept = !out_valid || m_axis_tready;
    wire input_handshake = s_axis_tvalid && s_axis_tready && enable;
    wire output_handshake = out_valid && m_axis_tready;

    assign s_axis_tready = can_accept && enable;
    assign m_axis_tdata  = out_tdata;
    assign m_axis_tkeep  = out_tkeep;
    assign m_axis_tlast  = out_tlast;
    assign m_axis_tvalid = out_valid;

    always @(posedge aclk) begin
        if (!aresetn) begin
            out_tdata <= {DATA_W{1'b0}};
            out_tkeep <= {N_LANES{1'b0}};
            out_tlast <= 1'b0;
            out_valid <= 1'b0;
        end else if (can_accept) begin
            if (s_axis_tvalid && enable) begin
                out_tdata <= transformed_data;
                out_tkeep <= s_axis_tkeep;
                out_tlast <= s_axis_tlast;
                out_valid <= 1'b1;
            end else if (m_axis_tready) begin
                out_valid <= 1'b0;
            end
        end
    end

    reg active;

    always @(posedge aclk) begin
        if (!aresetn || cnt_clear) begin
            input_beats   <= 32'd0;
            output_beats  <= 32'd0;
            stall_cycles  <= 32'd0;
            frame_count   <= 32'd0;
            active_cycles <= 32'd0;
            active        <= 1'b0;
        end else begin
            if (input_handshake)
                input_beats <= input_beats + 32'd1;

            if (output_handshake)
                output_beats <= output_beats + 32'd1;

            if (out_valid && !m_axis_tready)
                stall_cycles <= stall_cycles + 32'd1;

            if (output_handshake && out_tlast)
                frame_count <= frame_count + 32'd1;

            if (input_handshake && !active)
                active <= 1'b1;

            if (output_handshake && out_tlast)
                active <= 1'b0;

            if (active)
                active_cycles <= active_cycles + 32'd1;
        end
    end

endmodule
