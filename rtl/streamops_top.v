`timescale 1ns / 1ps

module streamops_top #(
    parameter DATA_W             = 64,
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 6,
    parameter VERSION_ID         = 32'h00010000
)(
    input  wire                                aclk,
    input  wire                                aresetn,

    // AXI4-Lite slave
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  wire [2:0]                          s_axi_awprot,
    input  wire                                s_axi_awvalid,
    output wire                                s_axi_awready,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]      s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0]    s_axi_wstrb,
    input  wire                                s_axi_wvalid,
    output wire                                s_axi_wready,

    output wire [1:0]                          s_axi_bresp,
    output wire                                s_axi_bvalid,
    input  wire                                s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]      s_axi_araddr,
    input  wire [2:0]                          s_axi_arprot,
    input  wire                                s_axi_arvalid,
    output wire                                s_axi_arready,

    output wire [C_S_AXI_DATA_WIDTH-1:0]      s_axi_rdata,
    output wire [1:0]                          s_axi_rresp,
    output wire                                s_axi_rvalid,
    input  wire                                s_axi_rready,

    // AXI4-Stream slave
    input  wire [DATA_W-1:0]                   s_axis_tdata,
    input  wire [DATA_W/8-1:0]                 s_axis_tkeep,
    input  wire                                s_axis_tvalid,
    output wire                                s_axis_tready,
    input  wire                                s_axis_tlast,

    // AXI4-Stream master
    output wire [DATA_W-1:0]                   m_axis_tdata,
    output wire [DATA_W/8-1:0]                 m_axis_tkeep,
    output wire                                m_axis_tvalid,
    input  wire                                m_axis_tready,
    output wire                                m_axis_tlast
);

    wire        w_enable;
    wire        w_soft_reset;
    wire        w_cnt_clear;
    wire [2:0]  w_mode;
    wire [7:0]  w_imm8;
    wire [7:0]  w_clamp_lo;
    wire [7:0]  w_clamp_hi;

    wire [31:0] w_input_beats;
    wire [31:0] w_output_beats;
    wire [31:0] w_stall_cycles;
    wire [31:0] w_frame_count;
    wire [31:0] w_active_cycles;

    wire axis_resetn = aresetn & ~w_soft_reset;

    streamops_axil_regs #(
        .C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH),
        .VERSION_ID         (VERSION_ID)
    ) u_regs (
        .s_axi_aclk     (aclk),
        .s_axi_aresetn  (aresetn),

        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

        .enable         (w_enable),
        .soft_reset     (w_soft_reset),
        .cnt_clear      (w_cnt_clear),
        .mode           (w_mode),
        .imm8           (w_imm8),
        .clamp_lo       (w_clamp_lo),
        .clamp_hi       (w_clamp_hi),

        .input_beats    (w_input_beats),
        .output_beats   (w_output_beats),
        .stall_cycles   (w_stall_cycles),
        .frame_count    (w_frame_count),
        .active_cycles  (w_active_cycles),
        .status_tready  (s_axis_tready),
        .status_tvalid  (m_axis_tvalid)
    );

    streamops_axis #(
        .DATA_W (DATA_W)
    ) u_axis (
        .aclk           (aclk),
        .aresetn        (axis_resetn),

        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tkeep   (s_axis_tkeep),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),

        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tkeep   (m_axis_tkeep),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast),

        .enable         (w_enable),
        .mode           (w_mode),
        .imm8           (w_imm8),
        .clamp_lo       (w_clamp_lo),
        .clamp_hi       (w_clamp_hi),
        .cnt_clear      (w_cnt_clear),

        .input_beats    (w_input_beats),
        .output_beats   (w_output_beats),
        .stall_cycles   (w_stall_cycles),
        .frame_count    (w_frame_count),
        .active_cycles  (w_active_cycles)
    );

endmodule
