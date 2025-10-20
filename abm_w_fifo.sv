
module abm_w_fifo #(
// IP enables
    parameter WRITE_EN              = 1,
    parameter READ_EN               = 0,
// AXI definitions
    parameter ADDR_W                = 32,
    parameter DATA_W                = 64,
    parameter LEN_W                 = 8,
    parameter LOCK_W                = 1,
    parameter QOS_W                 = 4,
    parameter CACHE_W               = 4,
    parameter ABURST_W              = 2,
    parameter PROT_W                = 3,
    parameter RESP_W                = 2,
    parameter REGION_W              = 4,
    parameter ID_W                  = 0,
// IP specific definitions
    parameter PAGE_SIZE_BYTES       = 4096,
    parameter SPLIT_PAGE_BOUNDARY   = 1, // 0: end burst at page boundary, >0: split burst at page boundary
    parameter BURST_POLICY          = 0, // 0: (safe) require full burst upfront, 1: stream, wait until data is present by lowering wvalid, 2: pad with dummy data if fifo empty
    parameter MISALIGN_ADJUST       = 0, // 0: disallow (results in error), >0: allow
    parameter ID_CHECK              = 0, // 0: disallow, >0: allow
// FIFOs
    parameter NUM_OUTSTANDING_WR    = 2,
    parameter NUM_OUTSTANDING_RD    = 2,

    parameter CMD_PUSH_STREAM_MODE  = 0,
    parameter DATA_PUSH_STREAM_MODE = 0,
    parameter RESP_POP_STREAM_MODE  = 0
)
(
//General
    //fifo_in_clk,
    //fifo_out_clk,
    //fifo_resetn,

// AXI
    m_axi_awaddr,
    m_axi_awprot,
    m_axi_awvalid,
    m_axi_awready,
    m_axi_awsize,
    m_axi_awburst,
    m_axi_awcache,
    m_axi_awlen,
    m_axi_awlock,
    m_axi_awqos,
    m_axi_awregion,
    m_axi_awid,
    m_axi_wdata,
    m_axi_wstrb,
    m_axi_wvalid,
    m_axi_wready,
    m_axi_wlast,
    m_axi_bresp,
    m_axi_bvalid,
    m_axi_bready,
    m_axi_bid,
    m_axi_araddr,
    m_axi_arprot,
    m_axi_arvalid,
    m_axi_arready,
    m_axi_arsize,
    m_axi_arburst,
    m_axi_arcache,
    m_axi_arlen,
    m_axi_arlock,
    m_axi_arqos,
    m_axi_arregion,
    m_axi_arid,
    m_axi_rready,
    m_axi_rdata,
    m_axi_rvalid,
    m_axi_rlast,
    m_axi_rid,
    m_axi_rresp,

    aclk,
    aresetn,

    wr_cmd_push_req,
    wr_cmd_push_struct_address,
    wr_cmd_push_struct_awlen,
    wr_cmd_push_struct_awsize,
    wr_cmd_push_struct_awid,
    wr_cmd_push_ack,

    wr_cmd_fifo_full,
    wr_cmd_fifo_empty,
    wr_cmd_fifo_count,

    wr_data_push_req,
    wr_data_push_struct_wdata,
    wr_data_push_struct_wstrb,
    wr_data_push_ack,

    wr_data_fifo_full,
    wr_data_fifo_empty,
    wr_data_fifo_count,
   
    wr_resp_pop_req,
    wr_resp_pop_struct_bresp,
    wr_resp_pop_struct_bid,
    wr_resp_pop_ack,

    wr_resp_fifo_full,
    wr_resp_fifo_empty,
    wr_resp_fifo_count
);
    // General
    localparam BYTE = 8;
    localparam PAGE_SIZE_BYTES_CLOG = $clog2(PAGE_SIZE_BYTES);
    localparam DATA_W_CLOG = $clog2(DATA_W);
    localparam DATA_W_BYTES = DATA_W/BYTE;
    localparam DATA_W_BYTES_CLOG = $clog2(DATA_W_BYTES);
    localparam STRB_W_CLOG = $clog2(DATA_W_BYTES);

    // AXI
    localparam STRB_W           = DATA_W_BYTES;
    localparam ASIZE_W          = DATA_W_BYTES_CLOG;
    localparam MAX_BURST_BEATS  = 1 << (LEN_W);

// PORT DECLARATION
/**************** Write Address Channel Signals ****************/
    output reg [ADDR_W-1:0]             m_axi_awaddr;    // address
    output reg [PROT_W-1:0]             m_axi_awprot;    // protection - privilege and securit level of transaction
    output reg                          m_axi_awvalid;   //
    input  wire                         m_axi_awready;   //
    output reg [ASIZE_W-1:0]            m_axi_awsize;    //3'b100, // burst size - size of each transfer in the burst 3'b100 for 16 bytes/ 128 bit
    output reg [ABURST_W-1:0]           m_axi_awburst;   // fixed burst = 00, incremental = 01, wrapped burst = 10
    output reg [CACHE_W-1:0]            m_axi_awcache;   // cache type - how transaction interacts with caches
    output reg [LEN_W-1:0]              m_axi_awlen;    // number of data transfers in the burst (0-255) (done)
    output reg [LOCK_W-1:0]             m_axi_awlock;    // lock type - indicates if transaction is part of locked sequence
    output reg [QOS_W-1:0]              m_axi_awqos;     // quality of service - transaction indication of priority level
    output reg [REGION_W-1:0]           m_axi_awregion;  // region identifier - identifies targetted region
    output reg [ID_W-1:0]               m_axi_awid;
/**************** Write Data Channel Signals ****************/
    output reg [DATA_W-1:0]             m_axi_wdata;     //
    output reg [STRB_W-1:0]             m_axi_wstrb;     //
    output reg                          m_axi_wvalid;    // set to 1 when data is ready to be transferred (done)
    input  wire                         m_axi_wready;    // 
    output reg                          m_axi_wlast;     // if awlen=0 then set wlast (done)
/**************** Write Response Channel Signals ****************/
    input  wire [RESP_W-1:0]            m_axi_bresp;     // write response - status of the write transaction (00 = okay, 01 = exokay, 10 = slverr, 11 = decerr)
    input  wire                         m_axi_bvalid;    // write response valid - 0 = response not valid, 1 = response is valid
    output reg                          m_axi_bready;    // write response ready - 0 = not ready, 1 = ready
    input  wire [ID_W-1:0]              m_axi_bid;
/**************** Read Address Channel Signals ****************/
    output reg [ADDR_W-1:0]             m_axi_araddr;    // read address
    output reg [PROT_W-1:0]             m_axi_arprot;    // protection - privilege and securit level of transaction
    output reg                          m_axi_arvalid;   // 
    input  wire                         m_axi_arready;   // 
    output reg [ASIZE_W-1:0]            m_axi_arsize;    //3'b100, // burst beat size - size of each transfer in the burst 3'b100 for 16 bytes/ 128 bit
    output reg [ABURST_W-1:0]           m_axi_arburst;   // fixed burst = 00, incremental = 01, wrapped burst = 10
    output reg [CACHE_W-1:0]            m_axi_arcache;   // cache type - how transaction interacts with caches
    output reg [LEN_W-1:0]              m_axi_arlen;     // number of data transfers in the burst (0-255) (done)
    output reg [LOCK_W-1:0]             m_axi_arlock;    // lock type - indicates if transaction is part of locked sequence
    output reg [QOS_W-1:0]              m_axi_arqos;     // quality of service - transaction indication of priority level
    output reg [REGION_W-1:0]           m_axi_arregion;  // region identifier - identifies targetted region
    output reg [ID_W-1:0]               m_axi_arid;
/**************** Read Data Channel Signals ****************/
    output reg                          m_axi_rready;    // read ready - 0 = not ready, 1 = ready
    input  wire [DATA_W-1:0]            m_axi_rdata;     // 
    input  wire                         m_axi_rvalid;    // read response valid - 0 = response not valid, 1 = response is valid
    input  wire                         m_axi_rlast;     // =1 when on last read
    input  wire [ID_W-1:0]              m_axi_rid;
/**************** Read Response Channel Signals ****************/
    input  wire [RESP_W-1:0]            m_axi_rresp;     // read response - status of the read transaction (00 = okay, 01 = exokay, 10 = slverr, 11 = decerr)
/**************** System Signals ****************/
    input wire                          aclk;
    input wire                          aresetn;
/**************** User Control Signals ****************/

// WR CMD pipe
    // (from external)
    input wire                  wr_cmd_push_req;
    input wire [(ADDR_W-1):0]   wr_cmd_push_struct_address;
    input wire [(LEN_W-1):0]    wr_cmd_push_struct_awlen;
    input wire [(ASIZE_W-1):0]  wr_cmd_push_struct_awsize;
    input wire [(ID_W-1):0]     wr_cmd_push_struct_awid;
    output wire                 wr_cmd_push_ack;
    // info
    output wire                                 wr_cmd_fifo_full;
    output wire                                 wr_cmd_fifo_empty;
    output wire [$clog2(NUM_OUTSTANDING_WR):0]  wr_cmd_fifo_count;

// WR DATA pipe
    // (from external)
    input wire                  wr_data_push_req;
    input wire [(DATA_W-1):0]   wr_data_push_struct_wdata;
    input wire [(STRB_W-1):0]   wr_data_push_struct_wstrb;
    output wire                 wr_data_push_ack;
    // info
    output wire                                                     wr_data_fifo_full;
    output wire                                                     wr_data_fifo_empty;
    output wire [$clog2(NUM_OUTSTANDING_WR * MAX_BURST_BEATS):0]    wr_data_fifo_count;

// WR RESP pipe
    // (to external)
    input wire                  wr_resp_pop_req;
    output wire [(RESP_W-1):0]  wr_resp_pop_struct_bresp;
    output wire [(ID_W-1):0]    wr_resp_pop_struct_bid;
    output wire                 wr_resp_pop_ack;
    // info
    output wire                                 wr_resp_fifo_full;
    output wire                                 wr_resp_fifo_empty;
    output wire [$clog2(NUM_OUTSTANDING_WR):0]  wr_resp_fifo_count;

/*******************************************************/

// FIFO INNER SIGNALS
// CMD POP
    wire                  wr_cmd_pop_req;
    wire [(ADDR_W-1):0]   wr_cmd_pop_struct_address;
    wire [(LEN_W-1):0]    wr_cmd_pop_struct_awlen;
    wire [(ASIZE_W-1):0]  wr_cmd_pop_struct_awsize;
    wire [(ID_W-1):0]     wr_cmd_pop_struct_awid;
    wire                  wr_cmd_pop_ack_pulse;

// RESP PUSH
    wire                  wr_resp_push_req;
    wire [(RESP_W-1):0]   wr_resp_push_struct_bresp;
    wire [(ID_W-1):0]     wr_resp_push_struct_bid;
    wire                  wr_resp_push_ack_pulse;

// DATA POP
    wire                  wr_data_pop_req;
    wire [(DATA_W-1):0]   wr_data_pop_struct_wdata;
    wire [(STRB_W-1):0]   wr_data_pop_struct_wstrb;
    wire                  wr_data_pop_ack_pulse;

/*******************************************************/

// write
    // cmd fifo
        // awaddr, awlen, awsize, awid -> lets say only incrementing burst is allowed....
    // data fifo
        // wdata, wstrb
    // resp fifo
        // bresp, bid
// read
    // cmd fifo
        // araddr, arlen, arsize, arburst, arid
    // resp fifo
        // rdata, rid, rlast, rresp

// BURST WR CMD + RESP FIFOs
    localparam WR_CMD_W = ADDR_W + LEN_W + ASIZE_W + ID_W;
    localparam WR_DATA_W = DATA_W + STRB_W;
    localparam WR_RESP_W = RESP_W + ID_W;

    wr_fifo_group #(
        .CMD_NUM_ENTRIES(NUM_OUTSTANDING_WR),
        .CMD_W(WR_CMD_W),
        .CMD_PUSH_STREAM_MODE(CMD_PUSH_STREAM_MODE),
        .CMD_POP_STREAM_MODE(1'b0),

        .DATA_NUM_ENTRIES(NUM_OUTSTANDING_WR * MAX_BURST_BEATS),
        .DATA_W(WR_DATA_W),
        .DATA_PUSH_STREAM_MODE(DATA_PUSH_STREAM_MODE),
        .DATA_POP_STREAM_MODE(1'b1),

        .RESP_NUM_ENTRIES(NUM_OUTSTANDING_WR),
        .RESP_W(WR_RESP_W),
        .RESP_PUSH_STREAM_MODE(1'b0),
        .RESP_POP_STREAM_MODE(RESP_POP_STREAM_MODE)
    ) wr_cmd_resp_data_fifos0
    (
        .clk(aclk),
        .resetn(aresetn),

// CMD FIFO
    // PUSH IN
        .cmd_push_req(wr_cmd_push_req), // in
        .cmd_push_struct({wr_cmd_push_struct_address, wr_cmd_push_struct_awlen, wr_cmd_push_struct_awsize, wr_cmd_push_struct_awid}), // in
        .cmd_push_ack(wr_cmd_push_ack), // out
        .cmd_push_ack_pulse(),

    // POP OUT
        .cmd_pop_req(wr_cmd_pop_req), // in
        .cmd_pop_struct({wr_cmd_pop_struct_address, wr_cmd_pop_struct_awlen, wr_cmd_pop_struct_awsize, wr_cmd_pop_struct_awid}), // out
        .cmd_pop_ack(),
        .cmd_pop_ack_pulse(wr_cmd_pop_ack_pulse), // out

    // INFO
        .cmd_fifo_full(wr_cmd_fifo_full),
        .cmd_fifo_empty(wr_cmd_fifo_empty),
        .cmd_fifo_count(wr_cmd_fifo_count),

// DATA FIFO 
    // PUSH IN
        .data_push_req(wr_data_push_req),
        .data_push_struct({wr_data_push_struct_wdata, wr_data_push_struct_wstrb}),
        .data_push_ack(wr_data_push_ack),
        .data_push_ack_pulse(),

    // POP OUT
        .data_pop_req(wr_data_pop_req), // in
        .data_pop_struct({wr_data_pop_struct_wdata, wr_data_pop_struct_wstrb}), // out
        .data_pop_ack(),
        .data_pop_ack_pulse(wr_data_pop_ack_pulse), // out

    // INFO
        .data_fifo_full(wr_data_fifo_full),
        .data_fifo_empty(wr_data_fifo_empty),
        .data_fifo_count(wr_data_fifo_count),
    
// RESP FIFO 
    // PUSH IN
        .resp_push_req(wr_resp_push_req), // in
        .resp_push_struct({wr_resp_push_struct_bresp, wr_resp_push_struct_bid}), // in
        .resp_push_ack(),
        .resp_push_ack_pulse(wr_resp_push_ack_pulse), // out

    // POP OUT
        .resp_pop_req(wr_resp_pop_req), // in
        .resp_pop_struct({wr_resp_pop_struct_bresp, wr_resp_pop_struct_bid}), // out
        .resp_pop_ack(wr_resp_pop_ack), // out
        .resp_pop_ack_pulse(),

    // INFO
        .resp_fifo_full(wr_resp_fifo_full),
        .resp_fifo_empty(wr_resp_fifo_empty),
        .resp_fifo_count(wr_resp_fifo_count)
    );


// AXI
    axi_burst_master #(
    // IP enables
        .WRITE_EN(WRITE_EN),
        .READ_EN(READ_EN),
    // AXI definitions
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
    // AXI
        .LEN_W(LEN_W),
        .LOCK_W(LOCK_W),
        .QOS_W(QOS_W),
        .CACHE_W(CACHE_W),
        .ABURST_W(ABURST_W),
        .PROT_W(PROT_W),
        .RESP_W(RESP_W),
        .REGION_W(REGION_W),
        .ID_W(ID_W),
    // IP specific definitions
        .PAGE_SIZE_BYTES(PAGE_SIZE_BYTES),
        .SPLIT_PAGE_BOUNDARY(SPLIT_PAGE_BOUNDARY),
        .BURST_POLICY(BURST_POLICY),
        .MISALIGN_ADJUST(MISALIGN_ADJUST),
        .ID_CHECK(ID_CHECK)
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
        .m_axi_awid(m_axi_awid),
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
        .m_axi_arid(m_axi_arid),
        /**************** Read Data Channel Signals ****************/
        .m_axi_rready(m_axi_rready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rlast(m_axi_rlast),
        /**************** Read Response Channel Signals ****************/
        .m_axi_rresp(m_axi_rresp),
        /**************** System Signals ****************/
        .aclk(aclk),
        .aresetn(aresetn),
        /**************** User Control Signals ****************/
    //write cmd
        .user_w_start(wr_cmd_pop_ack_pulse), // in
        .user_w_free(wr_cmd_pop_req), // out
    //write address
        .user_w_addr(wr_cmd_pop_struct_address), // in
        .user_w_len(wr_cmd_pop_struct_awlen), // in
        .user_w_awsize(wr_cmd_pop_struct_awsize), // in
        .user_w_awid(wr_cmd_pop_struct_awid), // in
    //write data
        .user_w_strb(wr_data_pop_struct_wstrb), // in
        .user_w_data(wr_data_pop_struct_wdata), // in
    //write data FIFO req/ack
        .user_w_wready(wr_data_pop_req), // out
        .user_w_wvalid(wr_data_pop_ack_pulse), // in
    //write response
        .user_w_bid(wr_resp_push_struct_bid), // out
        .user_w_status(wr_resp_push_struct_bresp), // out
    //write data req/ack
        .user_w_bvalid(wr_resp_push_req), // out
        .user_w_bready(wr_resp_push_ack_pulse), // in
    //write error
        .user_w_cmd_error(), // out
        .user_w_underrun_event(), // out
    //write data fifo
        .user_w_data_fifo_cnt(wr_data_fifo_cnt),
        .user_w_data_fifo_empty(wr_data_fifo_empty),
    // read cmd
        .user_r_start('h0),
        .user_r_len('h0),
        .user_r_addr('h0),
        .user_r_free(),
    // read response
        .user_r_status(),
        .user_r_data(),
    // read fifo
        .user_r_fifo_cnt('h0),
        .user_r_fifo_full('h0),
        .user_r_data_push_req()
    );


endmodule
