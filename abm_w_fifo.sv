
// Future:
// 1. allow parallel R/W
// 2. 4K boundary crossing

module abm_w_fifo #(
    //FIFO CTL
    parameter WRITE_BURST_DATA_NUM_ENTRIES,
    parameter READ_BURST_DATA_NUM_ENTRIES,

    //AXI
    parameter ADDR_W,
    parameter DATA_W,
    parameter WRITE_EN,
    parameter READ_EN,

)
(
//General
    input logic                 clk,
    input logic                 resetn,

    input logic                 cmd_start_req,
    output logic                cmd_start_ack,

//FIFO CTL
    // Status
    output wire                 wdata_fifo_full,
    output wire                 wdata_fifo_empty,

    output wire                 rdata_fifo_full,
    output wire                 rdata_fifo_empty,
    output wire                 rdata_fifo_pop_ready,

// AXI CMD
    input wire                  axi_cmd_op,
    input wire [ADDR_W-1:0]     axi_cmd_address,
    input wire [8-1:0]          axi_cmd_burst_len_in,

// Data for FIFO in
    input wire                  wdata_push_req, // rising pulse required; keep it high until you see ack
    // CMD
    input wire [DATA_W-1:0]     wdata_push_wdata,
    input wire [DATA_W/8-1:0]   wdata_push_wstrb,
    //
    output wire                 wdata_push_ack,
    output wire                 wdata_push_req_pulse,

//AXI RESP
    output wire [1:0]           axi_resp_status,

    // CPU side (RESP out)
    input wire                  rdata_pop_req, // rising pulse required; keep it high until you see ack
    // RESP
    output wire [DATA_W-1:0]    rdata_pop_rdata,
    //
    output wire                 rdata_pop_ack,
    output wire                 rdata_pop_req_pulse,

//AXI to DRAM
    /**************** Write Address Channel Signals ****************/
    output reg [ADDR_W-1:0]              m_axi_awaddr,    // address
    output reg [3-1:0]                   m_axi_awprot,    // protection - privilege and securit level of transaction
    output reg                           m_axi_awvalid,   //
    input  wire                          m_axi_awready,   //
    output reg [3-1:0]                   m_axi_awsize,    //3'b100, // burst size - size of each transfer in the burst 3'b100 for 16 bytes/ 128 bit
    output reg [2-1:0]                   m_axi_awburst,   // fixed burst = 00, incremental = 01, wrapped burst = 10
    output reg [4-1:0]                   m_axi_awcache,   // cache type - how transaction interacts with caches
    output reg [8-1:0]                   m_axi_awlen,     // number of data transfers in the burst (0-255) (done)
    output reg [1-1:0]                   m_axi_awlock,    // lock type - indicates if transaction is part of locked sequence
    output reg [4-1:0]                   m_axi_awqos,     // quality of service - transaction indication of priority level
    output reg [4-1:0]                   m_axi_awregion,  // region identifier - identifies targetted region
    /**************** Write Data Channel Signals ****************/
    output reg [DATA_W-1:0]              m_axi_wdata,     //
    output reg [DATA_W/8-1:0]            m_axi_wstrb,     //
    output reg                           m_axi_wvalid,    // set to 1 when data is ready to be transferred (done)
    input  wire                          m_axi_wready,    // 
    output reg                           m_axi_wlast,     // if awlen=0 then set wlast (done)
    /**************** Write Response Channel Signals ****************/
    input  wire [2-1:0]                  m_axi_bresp,     // write response - status of the write transaction (00 = okay, 01 = exokay, 10 = slverr, 11 = decerr)
    input  wire                          m_axi_bvalid,    // write response valid - 0 = response not valid, 1 = response is valid
    output reg                           m_axi_bready,    // write response ready - 0 = not ready, 1 = ready
    /**************** Read Address Channel Signals ****************/
    output reg [ADDR_W-1:0]              m_axi_araddr,    // read address
    output reg [3-1:0]                   m_axi_arprot,    // protection - privilege and securit level of transaction
    output reg                           m_axi_arvalid,   // 
    input  wire                          m_axi_arready,   // 
    output reg [3-1:0]                   m_axi_arsize,    //3'b100, // burst beat size - size of each transfer in the burst 3'b100 for 16 bytes/ 128 bit
    output reg [2-1:0]                   m_axi_arburst,   // fixed burst = 00, incremental = 01, wrapped burst = 10
    output reg [4-1:0]                   m_axi_arcache,   // cache type - how transaction interacts with caches
    output reg [8-1:0]                   m_axi_arlen,     // number of data transfers in the burst (0-255) (done)
    output reg [1-1:0]                   m_axi_arlock,    // lock type - indicates if transaction is part of locked sequence
    output reg [4-1:0]                   m_axi_arqos,     // quality of service - transaction indication of priority level
    output reg [4-1:0]                   m_axi_arregion,  // region identifier - identifies targetted region
    /**************** Read Data Channel Signals ****************/
    output reg                           m_axi_rready,    // read ready - 0 = not ready, 1 = ready
    input  wire [DATA_W-1:0]             m_axi_rdata,     // 
    input  wire                          m_axi_rvalid,    // read response valid - 0 = response not valid, 1 = response is valid
    input  wire                          m_axi_rlast,     // =1 when on last read
    /**************** Read Response Channel Signals ****************/
    input  wire [2-1:0]                  m_axi_rresp     // read response - status of the read transaction (00 = okay, 01 = exokay, 10 = slverr, 11 = decerr)
);

    logic user_free;

    logic start_cmd_ff;
    logic start_cmd_posedge;

    assign start_cmd_posedge = cmd_start_req && ~start_cmd_ff;

    logic axi_free_ff;
    logic axi_free_negedge;

    assign axi_free_negedge = ~user_free && axi_free_ff;

    logic start_cmd_final;

    always @ (posedge clk)
    begin
        if(~resetn)
        begin
            start_cmd_ff    <= 'h0;
            axi_free_ff     <= 'h0;
            start_cmd_final <= 'h0;
        end

        else
        begin
            start_cmd_ff    <= cmd_start_req;
            axi_free_ff     <= user_free;

            if(axi_free_negedge)    start_cmd_final <= 1'b0;

            else
            begin
                if(start_cmd_posedge)   start_cmd_final <= 1'b1;
            end
        end
    end

// PL side

    // DATA to fifo
    wire                 wdata_pop_req; // rising pulse required; keep it high until you see ack        
    wire [DATA_W-1:0]    wdata_pop_wdata;
    wire [DATA_W/8-1:0]  wdata_pop_wstrb;
    wire                 wdata_pop_req_pulse;

    // Data from fifo
    wire                  rdata_push_req; // rising pulse required; keep it high until you see ack
    wire [DATA_W-1:0]     rdata_push_rdata;

    fifo_ctl #(
        .CMD_NUM_ENTRIES(WRITE_BURST_DATA_NUM_ENTRIES),
        .CMD_W(DATA_W/8 + DATA_W),
        .RESP_NUM_ENTRIES(READ_BURST_DATA_NUM_ENTRIES),
        .RESP_W(DATA_W)
    ) burst_data_fifo_ctl0
    (
        .clk(clk),
        .resetn(resetn),

    // full + empty flags
        .cmd_fifo_full(wdata_fifo_full),
        .cmd_fifo_empty(wdata_fifo_empty),

        .resp_fifo_full(rdata_fifo_full),
        .resp_fifo_empty(rdata_fifo_empty),
        .resp_pop_ready(rdata_fifo_pop_ready),
    
    // CMD FIFO IN
        .cmd_push_req(wdata_push_req),
        .cmd_push_struct({wdata_push_wstrb,wdata_push_wdata}),
        .cmd_push_ack(wdata_push_ack),
        .cmd_push_req_pulse(wdata_push_req_pulse),

    // CMD FIFO OUT
        .cmd_pop_req(wdata_pop_req),
        .cmd_pop_struct({wdata_pop_wstrb,wdata_pop_wdata}),
        .cmd_pop_ack(),
        .cmd_pop_req_pulse(wdata_pop_req_pulse),
    
    // RESP FIFO IN
        .resp_push_req(rdata_push_req),
        .resp_push_struct(rdata_push_rdata),
        .resp_push_ack(),
        .resp_push_req_pulse(),

    // RESP FIFO OUT
        .resp_pop_req(rdata_pop_req),
        .resp_pop_struct(rdata_pop_rdata),
        .resp_pop_ack(rdata_pop_ack),
        .resp_pop_req_pulse(rdata_pop_req_pulse)
    );

// AXI signals
    logic user_stall_w_data;

    assign wdata_pop_req = user_free & ~user_stall_w_data; // signal driven by ~m_axi_wready

    logic user_status;
    logic user_status_ff;
    logic user_start;
    logic user_data_out_valid;

    axi_burst_master #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .WRITE_EN(WRITE_EN),
        .READ_EN(READ_EN)
    ) abm0
    (
        /**************** Write Address Channel Signals ****************/
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awqos(m_axi_awqos),
        .m_axi_awregion(m_axi_awregion),
        /**************** Write Data Channel Signals ****************/
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_wlast(m_axi_wlast),
        /**************** Write Response Channel Signals ****************/
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        /**************** Read Address Channel Signals ****************/
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arregion(m_axi_arregion),
        /**************** Read Data Channel Signals ****************/
        .m_axi_rready(m_axi_rready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rlast(m_axi_rlast),
        /**************** Read Response Channel Signals ****************/
        .m_axi_rresp(m_axi_rresp),
        /**************** System Signals ****************/
        .aclk(clk),
        .aresetn(resetn),
        /**************** User Control Signals ****************/  
        .user_start(start_cmd_final),

        // CMD in
        .user_w_r(axi_cmd_op),
        .user_addr_in(axi_cmd_address),
        .user_burst_len_in(axi_cmd_burst_len_in),

        // FIFO WDATA
        .user_data_strb(wdata_pop_wstrb),
        .user_data_in(wdata_pop_wdata),

        .user_free(user_free),
        .user_stall_w_data(user_stall_w_data),
        .user_stall_r_data(rdata_fifo_full),

        // RESP out
        .user_status(user_status),

        // FIFO RDATA
        .user_data_out(rdata_push_rdata),
        .user_data_out_valid(user_data_out_valid)
    );

    always @ (posedge clk)
    begin
        if(~resetn || start_cmd_final) user_status_ff <= 'h0;
        else
        begin
            user_status_ff <= user_status_ff | user_status;
        end
    end

    assign axi_resp_status = user_status_ff;

    assign rdata_push_req = user_data_out_valid;

endmodule
