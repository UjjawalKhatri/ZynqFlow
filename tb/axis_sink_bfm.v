`timescale 1ns / 1ps

module axis_sink_bfm #(
    parameter DATA_W    = 64,
    parameter MAX_BEATS = 16384
)(
    input  wire                 aclk,
    input  wire                 aresetn,

    input  wire [DATA_W-1:0]   s_axis_tdata,
    input  wire [DATA_W/8-1:0] s_axis_tkeep,
    input  wire                s_axis_tvalid,
    output reg                 s_axis_tready,
    input  wire                s_axis_tlast,

    input  wire                enable,
    input  wire                bp_enable,
    input  wire [7:0]          bp_probability,
    output reg  [31:0]         beat_count,
    output reg                 frame_done
);

    localparam N_BYTES = DATA_W / 8;

    reg [DATA_W-1:0]   sink_mem  [0:MAX_BEATS-1];
    reg [N_BYTES-1:0]  sink_keep [0:MAX_BEATS-1];
    reg                sink_last [0:MAX_BEATS-1];

    reg [31:0] rand_val;

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axis_tready <= 1'b0;
            beat_count    <= 32'd0;
            frame_done    <= 1'b0;
            rand_val      <= 32'd0;
        end else begin
            frame_done <= 1'b0;
            rand_val   <= $random;

            if (enable) begin
                if (bp_enable && (rand_val[7:0] < {24'd0, bp_probability})) begin
                    s_axis_tready <= 1'b0;
                end else begin
                    s_axis_tready <= 1'b1;
                end

                if (s_axis_tvalid && s_axis_tready) begin
                    sink_mem[beat_count]  <= s_axis_tdata;
                    sink_keep[beat_count] <= s_axis_tkeep;
                    sink_last[beat_count] <= s_axis_tlast;
                    beat_count <= beat_count + 32'd1;

                    if (s_axis_tlast)
                        frame_done <= 1'b1;
                end
            end else begin
                s_axis_tready <= 1'b0;
            end
        end
    end

endmodule
