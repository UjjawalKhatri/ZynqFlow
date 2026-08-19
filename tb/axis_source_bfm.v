`timescale 1ns / 1ps

module axis_source_bfm #(
    parameter DATA_W    = 64,
    parameter MAX_BEATS = 16384
)(
    input  wire                 aclk,
    input  wire                 aresetn,

    output reg  [DATA_W-1:0]   m_axis_tdata,
    output reg  [DATA_W/8-1:0] m_axis_tkeep,
    output reg                 m_axis_tvalid,
    input  wire                m_axis_tready,
    output reg                 m_axis_tlast,

    input  wire                start,
    input  wire [31:0]         num_beats,
    input  wire                gap_enable,
    input  wire [7:0]          gap_probability,
    output reg                 done
);

    localparam N_BYTES = DATA_W / 8;

    reg [DATA_W-1:0] source_mem [0:MAX_BEATS-1];
    reg [31:0] beat_idx;
    reg        running;
    reg [31:0] rand_val;

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tdata  <= {DATA_W{1'b0}};
            m_axis_tkeep  <= {N_BYTES{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            done          <= 1'b0;
            beat_idx      <= 32'd0;
            running       <= 1'b0;
            rand_val      <= 32'd0;
        end else if (start && !running) begin
            running       <= 1'b1;
            beat_idx      <= 32'd0;
            done          <= 1'b0;
            m_axis_tdata  <= source_mem[0];
            m_axis_tkeep  <= {N_BYTES{1'b1}};
            m_axis_tlast  <= (num_beats == 32'd1) ? 1'b1 : 1'b0;
            m_axis_tvalid <= 1'b1;
        end else if (running) begin
            rand_val <= $random;

            if (m_axis_tvalid && m_axis_tready) begin
                if (beat_idx == num_beats - 1) begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    running       <= 1'b0;
                    done          <= 1'b1;
                end else begin
                    beat_idx <= beat_idx + 32'd1;
                    if (gap_enable && (rand_val[7:0] < {24'd0, gap_probability})) begin
                        m_axis_tvalid <= 1'b0;
                    end else begin
                        m_axis_tdata  <= source_mem[beat_idx + 1];
                        m_axis_tkeep  <= {N_BYTES{1'b1}};
                        m_axis_tlast  <= (beat_idx + 1 == num_beats - 1) ? 1'b1 : 1'b0;
                        m_axis_tvalid <= 1'b1;
                    end
                end
            end else if (!m_axis_tvalid) begin
                if (gap_enable && (rand_val[15:8] < {24'd0, gap_probability})) begin
                    m_axis_tvalid <= 1'b0;
                end else begin
                    m_axis_tdata  <= source_mem[beat_idx];
                    m_axis_tkeep  <= {N_BYTES{1'b1}};
                    m_axis_tlast  <= (beat_idx == num_beats - 1) ? 1'b1 : 1'b0;
                    m_axis_tvalid <= 1'b1;
                end
            end
        end
    end

endmodule
