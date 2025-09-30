

module abm_w_fifo #(
// IP enables
    parameter WRITE_EN           = 1,
    parameter READ_EN            = 1,
// AXI definitions
    parameter ADDR_W             = 32,
    parameter DATA_W             = 64,
    parameter LEN_W              = 8,
    parameter LOCK_W             = 1,
    parameter QOS_W              = 4,
    parameter CACHE_W            = 4,
    parameter ABURST_W           = 2,
    parameter PROT_W             = 3,
    parameter RESP_W             = 2,
    parameter REGION_W           = 4,
    parameter ID_W               = 0,
// IP specific definitions
    parameter PAGE_SIZE_BYTES       = 4096,
    parameter SPLIT_PAGE_BOUNDARY   = 1, // 0: end burst at page boundary, >0: split burst at page boundary
    parameter BURST_POLICY          = 0, // 0: (safe) require full burst upfront, 1: stream, wait until data is present by lowering wvalid, 2: pad with dummy data if fifo empty
    parameter MISALIGN_ADJUST       = 0 // 0: disallow (results in error), >0: allow
// FIFO
    parameter 
)
(
//General
    fifo_in_clk,
    fifo_out_clk,
    fifo_resetn,

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
    m_axi_wdata,
    m_axi_wstrb,
    m_axi_wvalid,
    m_axi_wready,
    m_axi_wlast,
    m_axi_bresp,
    m_axi_bvalid,
    m_axi_bready,
    m_axi_araddr,
    m_axi_arprot,
    m_axi_arvalid,
    m_axi_arready,
    m_axi_arsize,
    m_axi_arcache,
    m_axi_arlen,
    m_axi_arlock,
    m_axi_arqos,
    m_axi_arregion,
    m_axi_rready,
    m_axi_rdata,
    m_axi_rvalid,
    m_axi_rlast,
    m_axi_rresp,
    aclk,
    aresetn,
    cmd_fifo_full,
    cmd_fifo_empty,
    cmd_fifo_count,
    resp_fifo_full,
    resp_fifo_empty,
    resp_fifo_count,
    resp_pop_ready,
    cmd_push_req,
    cmd_push_struct_op,
    cmd_push_struct_address,
    cmd_push_struct_wdata,
    cmd_push_struct_wstrb,
    cmd_push_ack,
    cmd_push_req_pulse,
    cmd_pop_req,
    cmd_pop_struct_op,
    cmd_pop_struct_address,
    cmd_pop_struct_wdata,
    cmd_pop_struct_wstrb,
    cmd_pop_ack,
    cmd_pop_req_pulse,
    resp_push_req,
    resp_push_struct_op,
    resp_push_struct_address,
    resp_push_struct_rdata,
    resp_push_struct_status,
    resp_push_ack,
    resp_push_req_pulse,
    resp_pop_req,
    resp_pop_struct_op,
    resp_pop_struct_address,
    resp_pop_struct_rdata,
    resp_pop_struct_status,
    resp_pop_ack,
    resp_pop_req_pulse
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
    output wire                             cmd_fifo_full;
    output wire                             cmd_fifo_empty;
    output wire [$clog2(CMD_NUM_ENTRIES):0] cmd_fifo_count;

    output wire                              resp_fifo_full;
    output wire                              resp_fifo_empty;
    output wire [$clog2(RESP_NUM_ENTRIES):0] resp_fifo_count;
    output wire                              resp_pop_ready;

// CMD pipe
    // (CMD in)
    input wire                  cmd_push_req; // rising pulse required; keep it high until you see ack
    input wire                  cmd_push_struct_op;
    input wire [ADDR_W-1:0]     cmd_push_struct_address;
    input wire [DATA_W-1:0]     cmd_push_struct_wdata;
    input wire [DATA_W/8-1:0]   cmd_push_struct_wstrb;
    output wire                 cmd_push_ack;
    output wire                 cmd_push_req_pulse;

// RESP pipe
    // (RESP out)
    input wire                  resp_pop_req; // rising pulse required; keep it high until you see ack
    output wire                 resp_pop_struct_op;
    output wire [ADDR_W-1:0]    resp_pop_struct_address;
    output wire [DATA_W-1:0]    resp_pop_struct_rdata;
    output wire [2-1:0]         resp_pop_struct_status;
    output wire                 resp_pop_ack;
    output wire                 resp_pop_req_pulse;
/*******************************************************/

// FIFO
    localparam CMD_FIFO_DATA_WIDTH  = 1 + ADDR_W + DATA_W + (DATA_W / 8);
    localparam RESP_FIFO_DATA_WIDTH = 1 + ADDR_W + DATA_W + 2;

    // PL side (CMD out)
    wire                  cmd_pop_req; // rising pulse required; keep it high until you see ack        
    wire                  cmd_pop_struct_op;
    wire [ADDR_W-1:0]     cmd_pop_struct_address;
    wire [DATA_W-1:0]     cmd_pop_struct_wdata;
    wire [DATA_W/8-1:0]   cmd_pop_struct_wstrb;
    wire                  cmd_pop_ack;
    wire                  cmd_pop_req_pulse;

    assign cmd_pop_req = user_w_free;
    assign user_w_start = cmd_pop_ack;

        // (RESP in)
    wire                  resp_push_req; // rising pulse required; keep it high until you see ack
    wire                  resp_push_struct_op;
    wire [ADDR_W-1:0]     resp_push_struct_address;
    wire [DATA_W-1:0]     resp_push_struct_rdata;
    wire [2-1:0]          resp_push_struct_status;
    wire                  resp_push_ack;
    wire                  resp_push_req_pulse;

    fifo_ctl #(
        .CMD_NUM_ENTRIES(MAX_BURST_BEATS),
        .CMD_W(CMD_FIFO_DATA_WIDTH),
        .RESP_NUM_ENTRIES(MAX_BURST_BEATS),
        .RESP_W(RESP_FIFO_DATA_WIDTH)
    ) burst_data_fifo_ctl0
    (
        .clk(clk),
        .resetn(resetn),

    // CMD FIFO IN
        .cmd_push_req(cmd_push_req),
        .cmd_push_struct({cmd_push_struct_op,cmd_push_struct_address,cmd_push_struct_wdata,cmd_push_struct_wstrb}),
        .cmd_push_ack(cmd_push_ack),
        .cmd_push_req_pulse(cmd_push_req_pulse),

    // CMD FIFO OUT
        .cmd_pop_req(cmd_pop_req),
        .cmd_pop_struct({cmd_pop_struct_op,cmd_pop_struct_address,cmd_pop_struct_wdata,cmd_pop_struct_wstrb}),
        .cmd_pop_ack(cmd_pop_ack),
        .cmd_pop_req_pulse(cmd_pop_req_pulse),

    // CMD FIFO INFO
        .cmd_fifo_full(cmd_fifo_full),
        .cmd_fifo_empty(cmd_fifo_empty),
        .cmd_fifo_count(cmd_fifo_count),
    
    // RESP FIFO IN
        .resp_push_req(resp_push_req),
        .resp_push_struct({resp_push_struct_op,resp_push_struct_address,resp_push_struct_rdata,resp_push_struct_status}),
        .resp_push_ack(resp_push_ack),
        .resp_push_req_pulse(resp_push_req_pulse),

    // RESP FIFO OUT
        .resp_pop_req(resp_pop_req),
        .resp_pop_struct({resp_pop_struct_op,resp_pop_struct_address,resp_pop_struct_rdata,resp_pop_struct_status}),
        .resp_pop_ack(resp_pop_ack),
        .resp_pop_req_pulse(resp_pop_req_pulse),

    // RESP FIFO INFO
        .resp_fifo_full(resp_fifo_full),
        .resp_fifo_empty(resp_fifo_empty),
        .resp_fifo_count(resp_fifo_count),
        .resp_pop_ready(resp_pop_ready)
    );

// AXI signals
    //write
    wire                         user_w_start;
    wire [LEN_W-1:0]             user_w_len;
    wire [ADDR_W-1:0]            user_w_addr;
    wire [RESP_W-1:0]            user_w_status; // 00:OKAY, 01:EXOKAY, 10:SLVERR, 11:DECERR
    wire                         user_w_free;
    wire [3:0]                   user_w_cmd_error; // 00:OKAY, 01:NOROOM (1 beat can't fit before next page boundary), 
    wire                         user_w_underrun_event;
    //write data
    wire [STRB_W-1:0]            user_w_strb;
    wire [DATA_W-1:0]            user_w_data;
    wire [LEN_W-1:0]             user_w_fifo_cnt;
    wire                         user_w_fifo_empty;
    wire                         user_w_data_pop_req;

    //read
    wire                         user_r_start;
    wire [LEN_W-1:0]             user_r_len;
    wire [ADDR_W-1:0]            user_r_addr;
    wire [RESP_W-1:0]            user_r_status;
    wire                         user_r_free;
    //read data
    wire [DATA_W-1:0]            user_r_data;
    wire [LEN_W-1:0]             user_r_fifo_cnt;
    wire                         user_r_fifo_full;
    wire                         user_r_data_push_req;

// FIFO to AXI MUX (AXI-R/W share fifos)
    always_comb
    begin
        if(cmd_pop_ack)
        begin
            if(cmd_pop_struct_op == 0) // write
            begin

            end

            else if(cmd_pop_struct_op == 1) // read
            begin
            
            end
        end
    end

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
        .MISALIGN_ADJUST(MISALIGN_ADJUST)
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
    // write cmd
        .user_w_start(user_w_start),
        .user_w_len(user_w_len),
        .user_w_addr(user_w_addr),    
        .user_w_free(user_w_free),
    // write data
        .user_w_strb(user_w_strb),
        .user_w_data(user_w_data),
    // write response
        .user_w_status(user_w_status),
        .user_w_cmd_error(user_w_cmd_error),
        .user_w_underrun_event(user_w_underrun_event),
    // write fifo
        .user_w_fifo_cnt(user_w_fifo_cnt),
        .user_w_fifo_empty(user_w_fifo_empty),
        .user_w_data_pop_req(user_w_data_pop_req),
    // read cmd
        .user_r_start(),
        .user_r_len(),
        .user_r_addr(),
        .user_r_free(),
    // read response
        .user_r_status(),
        .user_r_data(),
    // read fifo
        .user_r_fifo_cnt(),
        .user_r_fifo_full(),
        .user_r_data_push_req()
    );


endmodule
