`timescale 1ns / 1ps

module streamops_axil_regs #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 6,
    parameter VERSION_ID         = 32'h00010000
)(
    input  wire                                s_axi_aclk,
    input  wire                                s_axi_aresetn,

    // Write address
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  wire [2:0]                          s_axi_awprot,
    input  wire                                s_axi_awvalid,
    output wire                                s_axi_awready,

    // Write data
    input  wire [C_S_AXI_DATA_WIDTH-1:0]      s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0]    s_axi_wstrb,
    input  wire                                s_axi_wvalid,
    output wire                                s_axi_wready,

    // Write response
    output wire [1:0]                          s_axi_bresp,
    output wire                                s_axi_bvalid,
    input  wire                                s_axi_bready,

    // Read address
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]      s_axi_araddr,
    input  wire [2:0]                          s_axi_arprot,
    input  wire                                s_axi_arvalid,
    output wire                                s_axi_arready,

    // Read data
    output wire [C_S_AXI_DATA_WIDTH-1:0]      s_axi_rdata,
    output wire [1:0]                          s_axi_rresp,
    output wire                                s_axi_rvalid,
    input  wire                                s_axi_rready,

    // Datapath controls
    output wire                                enable,
    output wire                                soft_reset,
    output wire                                cnt_clear,
    output wire [2:0]                          mode,
    output wire [7:0]                          imm8,
    output wire [7:0]                          clamp_lo,
    output wire [7:0]                          clamp_hi,

    // Datapath status & counters
    input  wire [31:0]                         input_beats,
    input  wire [31:0]                         output_beats,
    input  wire [31:0]                         stall_cycles,
    input  wire [31:0]                         frame_count,
    input  wire [31:0]                         active_cycles,
    input  wire                                status_tready,
    input  wire                                status_tvalid
);

    localparam ADDR_CTRL          = 6'h00;
    localparam ADDR_MODE          = 6'h04;
    localparam ADDR_IMM8          = 6'h08;
    localparam ADDR_CLAMP         = 6'h0C;
    localparam ADDR_STATUS        = 6'h10;
    localparam ADDR_INPUT_BEATS   = 6'h14;
    localparam ADDR_OUTPUT_BEATS  = 6'h18;
    localparam ADDR_STALL_CYCLES  = 6'h1C;
    localparam ADDR_FRAME_COUNT   = 6'h20;
    localparam ADDR_ACTIVE_CYCLES = 6'h24;
    localparam ADDR_VERSION       = 6'h28;

    reg [31:0] reg_ctrl;
    reg [31:0] reg_mode;
    reg [31:0] reg_imm8;
    reg [31:0] reg_clamp;

    reg aw_ready_r;
    reg w_ready_r;
    reg [1:0] b_resp_r;
    reg b_valid_r;
    reg [C_S_AXI_ADDR_WIDTH-1:0] aw_addr_r;
    reg aw_done;
    reg w_done;

    assign s_axi_awready = aw_ready_r;
    assign s_axi_wready  = w_ready_r;
    assign s_axi_bresp   = b_resp_r;
    assign s_axi_bvalid  = b_valid_r;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            aw_ready_r <= 1'b0;
            aw_addr_r  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            aw_done    <= 1'b0;
        end else begin
            if (!aw_done && s_axi_awvalid && !aw_ready_r) begin
                aw_ready_r <= 1'b1;
                aw_addr_r  <= s_axi_awaddr;
                aw_done    <= 1'b1;
            end else begin
                aw_ready_r <= 1'b0;
            end
            if (b_valid_r && s_axi_bready)
                aw_done <= 1'b0;
        end
    end

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            w_ready_r <= 1'b0;
            w_done    <= 1'b0;
        end else begin
            if (!w_done && s_axi_wvalid && !w_ready_r) begin
                w_ready_r <= 1'b1;
                w_done    <= 1'b1;
            end else begin
                w_ready_r <= 1'b0;
            end
            if (b_valid_r && s_axi_bready)
                w_done <= 1'b0;
        end
    end

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            b_valid_r <= 1'b0;
            b_resp_r  <= 2'b00;
        end else begin
            if (aw_done && w_done && !b_valid_r) begin
                b_valid_r <= 1'b1;
                b_resp_r  <= 2'b00;
            end else if (b_valid_r && s_axi_bready) begin
                b_valid_r <= 1'b0;
            end
        end
    end

    wire write_en = aw_done && w_done && !b_valid_r;
    reg cnt_clear_r;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            reg_ctrl    <= 32'd0;
            reg_mode    <= 32'd0;
            reg_imm8    <= 32'd0;
            reg_clamp   <= 32'd0;
            cnt_clear_r <= 1'b0;
        end else begin
            if (cnt_clear_r) begin
                reg_ctrl[1] <= 1'b0;
                cnt_clear_r <= 1'b0;
            end

            if (write_en) begin
                case (aw_addr_r)
                    ADDR_CTRL: begin
                        if (s_axi_wstrb[0]) reg_ctrl[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_ctrl[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_ctrl[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_ctrl[31:24] <= s_axi_wdata[31:24];
                        if (s_axi_wstrb[0] && s_axi_wdata[1])
                            cnt_clear_r <= 1'b1;
                    end
                    ADDR_MODE: begin
                        if (s_axi_wstrb[0]) reg_mode[7:0] <= s_axi_wdata[7:0];
                    end
                    ADDR_IMM8: begin
                        if (s_axi_wstrb[0]) reg_imm8[7:0] <= s_axi_wdata[7:0];
                    end
                    ADDR_CLAMP: begin
                        if (s_axi_wstrb[0]) reg_clamp[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_clamp[15:8] <= s_axi_wdata[15:8];
                    end
                    default: ;
                endcase
            end
        end
    end

    reg ar_ready_r;
    reg [C_S_AXI_DATA_WIDTH-1:0] r_data_r;
    reg [1:0] r_resp_r;
    reg r_valid_r;

    assign s_axi_arready = ar_ready_r;
    assign s_axi_rdata   = r_data_r;
    assign s_axi_rresp   = r_resp_r;
    assign s_axi_rvalid  = r_valid_r;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            ar_ready_r <= 1'b0;
            r_data_r   <= 32'd0;
            r_resp_r   <= 2'b00;
            r_valid_r  <= 1'b0;
        end else begin
            if (s_axi_arvalid && !ar_ready_r && !r_valid_r) begin
                ar_ready_r <= 1'b1;
                r_resp_r   <= 2'b00;

                case (s_axi_araddr)
                    ADDR_CTRL:          r_data_r <= reg_ctrl;
                    ADDR_MODE:          r_data_r <= reg_mode;
                    ADDR_IMM8:          r_data_r <= reg_imm8;
                    ADDR_CLAMP:         r_data_r <= reg_clamp;
                    ADDR_STATUS:        r_data_r <= {29'd0, status_tvalid, status_tready, reg_ctrl[0]};
                    ADDR_INPUT_BEATS:   r_data_r <= input_beats;
                    ADDR_OUTPUT_BEATS:  r_data_r <= output_beats;
                    ADDR_STALL_CYCLES:  r_data_r <= stall_cycles;
                    ADDR_FRAME_COUNT:   r_data_r <= frame_count;
                    ADDR_ACTIVE_CYCLES: r_data_r <= active_cycles;
                    ADDR_VERSION:       r_data_r <= VERSION_ID;
                    default:            r_data_r <= 32'hDEADBEEF;
                endcase
            end else begin
                ar_ready_r <= 1'b0;
            end

            if (ar_ready_r) begin
                r_valid_r <= 1'b1;
            end else if (r_valid_r && s_axi_rready) begin
                r_valid_r <= 1'b0;
            end
        end
    end

    assign enable     = reg_ctrl[0];
    assign cnt_clear  = reg_ctrl[1];
    assign soft_reset = reg_ctrl[2];
    assign mode       = reg_mode[2:0];
    assign imm8       = reg_imm8[7:0];
    assign clamp_lo   = reg_clamp[7:0];
    assign clamp_hi   = reg_clamp[15:8];

endmodule
