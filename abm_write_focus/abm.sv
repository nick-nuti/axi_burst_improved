
// SIGNALS NOT CURRENTLY USED:
    // LOCK     : AWLOCK/ARLOCK , locked transactions (exclusive) ; only useful for atomic operations (DRAM doesn't use this?)
    // QOS      : AWQOS/ARQOS , priority hint for arbiter; useful for multiple masters competing for DRAM
    // REGION   : AWREGION/ARREGION , extra routing bits for complex interconnects; apparently for multi-SoC systems with complex routing
    // CACHE    : awcache/arcache , cacheability hint (bufferable, modifiable); DRAM apparently ties this to 0011 (normal non-cacheable bufferable) or 0010 (non-cacheable) 
    // PROT     : awprot/arprot , typically 000 unless implementing privilege domains

// FUTURE REQUIREMENTS
    // command fifo: {awid, awaddr, awlen, awsize, awburst, awprot, awcache, awqos, awregion}
    // data fifo: {wdata, wstrb}
    // resp fifo: {bresp, bid}
    
// NEED TO DO:
    // I may need to make an AXI-smart connect type of IP that can multiplex multiple IP master ports
        // this is where ID_CHECK + number outstanding requests would make sense
        // ID CHECK:
            // - this is only needed if system doesn't wait for bresp (repeatedly send bursts)
            // - would require ID tracking, number writes outstanding
            // - this allows "out of order transaction responses"
            // - IF command processor, memory scheduler (all of them share one master)... start issuing multiple bursts per engine then yes this is required

    // WRITE:
        // - need to add ID check error that's always active (compares awid to bid and if these don't match then error out)
        // - still need to do verification for misaligned address, split burst, each different burst policy, and (misaligned address + split burst)
    // READ:
        // - everything

module axi_burst_master #(
// IP enables
    parameter WRITE_EN          =1,
    parameter READ_EN           =1,
// AXI definitions
    parameter ADDR_W            =32,
    parameter DATA_W            =64,
    // AXI
    parameter LEN_W             = 8,
    parameter LOCK_W            = 1,
    parameter QOS_W             = 4,
    parameter CACHE_W           = 4,
    parameter ABURST_W          = 2,
    parameter PROT_W            = 3,
    parameter RESP_W            = 2,
    parameter REGION_W          = 4,
    parameter ID_W              = 0,

// IP specific definitions
    parameter PAGE_SIZE_BYTES       = 4096,
    parameter SPLIT_PAGE_BOUNDARY   = 0, // 0: end burst at page boundary, >0: split burst at page boundary
    parameter BURST_POLICY          = 0, // 0: (safe) require full burst upfront, 1: stream, wait until data is present by lowering wvalid, 2: pad with dummy data if fifo empty
    parameter MISALIGN_ADJUST       = 0, // 0: disallow (results in error), >0: allow
    parameter ID_CHECK              = 0  // 0: id checking error disabled, >0: id checking error enabled
)
(
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

    user_w_start,
    user_w_free,

    user_w_addr,
    user_w_len,
    user_w_awsize,
    user_w_awid,

    user_w_strb,
    user_w_data,

    user_w_wready,
    user_w_wvalid,

    user_w_bid,
    user_w_status,

    user_w_bvalid,
    user_w_bready,

    user_w_cmd_error,
    user_w_underrun_event,

    user_w_data_fifo_cnt,
    user_w_data_fifo_empty,
    //user_w_data_pop_req,

    user_r_start,
    user_r_len,
    user_r_addr,
    user_r_status,
    user_r_free,
    user_r_data,
    user_r_fifo_cnt,
    user_r_fifo_full,
    user_r_data_push_req
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
    input  logic                         m_axi_awready;   //
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
    input  logic                         m_axi_wready;    // 
    output reg                          m_axi_wlast;     // if awlen=0 then set wlast (done)
/**************** Write Response Channel Signals ****************/
    input  logic [RESP_W-1:0]            m_axi_bresp;     // write response - status of the write transaction (00 = okay, 01 = exokay, 10 = slverr, 11 = decerr)
    input  logic                         m_axi_bvalid;    // write response valid - 0 = response not valid, 1 = response is valid
    output reg                           m_axi_bready;    // write response ready - 0 = not ready, 1 = ready
    input  logic [ID_W-1:0]              m_axi_bid;
/**************** Read Address Channel Signals ****************/
    output reg [ADDR_W-1:0]             m_axi_araddr;    // read address
    output reg [PROT_W-1:0]             m_axi_arprot;    // protection - privilege and securit level of transaction
    output reg                          m_axi_arvalid;   // 
    input  logic                        m_axi_arready;   // 
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
    input  logic [DATA_W-1:0]            m_axi_rdata;     // 
    input  logic                         m_axi_rvalid;    // read response valid - 0 = response not valid, 1 = response is valid
    input  logic                         m_axi_rlast;     // =1 when on last read
    input  logic [ID_W-1:0]              m_axi_rid;
/**************** Read Response Channel Signals ****************/
    input  logic [RESP_W-1:0]            m_axi_rresp;     // read response - status of the read transaction (00 = okay, 01 = exokay, 10 = slverr, 11 = decerr)
/**************** System Signals ****************/
    input logic                          aclk;
    input logic                          aresetn; 
/**************** User Control Signals ****************/
//write cmd
    input  logic                         user_w_start;
    output logic                         user_w_free;
//write address
    input  logic [ADDR_W-1:0]            user_w_addr;
    input  logic [LEN_W-1:0]             user_w_len;
    input  logic [ASIZE_W-1:0]           user_w_awsize;
    input  logic [ID_W-1:0]              user_w_awid;
//write data
    input  logic [STRB_W-1:0]            user_w_strb;
    input  logic [DATA_W-1:0]            user_w_data;
//write data FIFO req/ack
    output logic                         user_w_wready; // req
    input  logic                         user_w_wvalid; // ack
//write response
    output logic [ID_W-1:0]              user_w_bid;
    output logic [RESP_W-1:0]            user_w_status; // 00:OKAY, 01:EXOKAY, 10:SLVERR, 11:DECERR
//write data req/ack
    output logic                         user_w_bvalid; // req
    input  logic                         user_w_bready; // ack
//write error
    output logic [3:0]                   user_w_cmd_error; // 00:OKAY, 01:NOROOM (1 beat can't fit before next page boundary), 
    output logic                         user_w_underrun_event;
//write fifo
    input  logic [LEN_W:0]               user_w_data_fifo_cnt; // increased the size by 1...
    input  logic                         user_w_data_fifo_empty;
    //output logic                         user_w_data_pop_req;
//read cmd
    input  logic                         user_r_start;
    input  logic [LEN_W-1:0]             user_r_len;
    input  logic [ADDR_W-1:0]            user_r_addr;
    output logic [RESP_W-1:0]            user_r_status;
    output logic                         user_r_free;
//read response
    output logic [DATA_W-1:0]            user_r_data;
//read fifo
    input  logic [LEN_W-1:0]             user_r_fifo_cnt;
    input  logic                         user_r_fifo_full;
    output reg                           user_r_data_push_req;
/*******************************************************/

// ---- Misaligned Address ---- //
reg  [DATA_W_BYTES_CLOG-1:0]    w_addr_offset_ff;

reg [DATA_W-1:0] carry_w_data_ff;
reg [STRB_W-1:0] carry_w_strb_ff;

logic [DATA_W-1:0] aligned_w_data;
logic [DATA_W-1:0] carry_w_data;
logic [DATA_W-1:0] aligned_w_data_final;
logic [STRB_W-1:0] aligned_w_strb;
logic [STRB_W-1:0] carry_w_strb;
logic [STRB_W-1:0] aligned_w_strb_final;

logic [DATA_W_CLOG-1:0] w_data_shift_left;
logic [DATA_W_CLOG-1:0] w_data_shift_right;

logic [STRB_W_CLOG-1:0] w_strb_shift_left;
logic [STRB_W_CLOG-1:0] w_strb_shift_right;
// aligner
logic                  align_carry_valid_ff;
logic [DATA_W-1:0]     align_carry_w_data_ff;
logic [DATA_W/8-1:0]   align_carry_w_strb_ff;
// splitter
logic                  split_carry_valid_ff;
logic [DATA_W-1:0]     split_carry_w_data_ff;
logic [DATA_W/8-1:0]   split_carry_w_strb_ff;

// AXI W ---------------------------------------------------
generate
    if(WRITE_EN)
    begin

        logic                   start_write;
        reg [4:0]               axi_w_cs, axi_w_ns;
        reg [LEN_W-1:0]         w_data_counter;
        reg [LEN_W-1:0]         user_w_len_ff;
        reg [ADDR_W-1:0]        user_w_addr_ff;
        reg [ASIZE_W-1:0]       user_w_awsize_ff;
        reg [ID_W-1:0]          user_w_awid_ff;
        reg                     ready_w_flag;
        reg                     start_w_ff;
        logic                    next_w_feed_in;
        logic                   burst_w_split_flag_ff;
        logic                   misalign_w_addr_flag_ff;
        logic [ADDR_W-1:0]      addr_w_tmp_ff;
        logic [LEN_W-1:0]       len_w_tmp_ff;
        logic [ADDR_W-1:0]      addr_w_split_tmp_ff;
        logic [LEN_W-1:0]       len_w_split_tmp_ff;
        logic [ADDR_W-1:0]      bytes_until_boundary;
        //logic [LEN_W-1:0]       beats_until_boundary;
        logic [ADDR_W-1:0]       beats_until_boundary;
        logic [LEN_W-1:0]       awlen_until_boundary;
        logic [3:0]             error_wrap;
        logic                   error_redux_or;
        logic                    no_beats_fit_flag;
        logic                    page_boundary_cross_no_split_flag;
        logic                    insufficient_wdata_flag;
        logic                    start_w_addr_misalign_flag;
        logic [3:0]             user_w_cmd_error_ff;
        logic                   underrun_flag_ff;

        logic [DATA_W-1:0]       w_data_final;
        logic [STRB_W-1:0]       w_strb_final;

        logic [LEN_W + DATA_W_BYTES_CLOG:0] total_bytes;
        logic [DATA_W_BYTES_CLOG-1:0] misalign_bytes;
        logic [LEN_W:0] beats_required;
        logic [LEN_W:0] beats_decided;
        logic [LEN_W:0] awlen_decided;
        logic [LEN_W:0] awlen_split;
        
        
// ---- FSM ---- //
        localparam WRITE_IDLE       = 'b00001;
        localparam WRITE_CHK_CMD    = 'b00010;
        localparam WRITE_ADDRESS    = 'b00100;
        localparam WRITE            = 'b01000;
        localparam WRITE_RESPONSE   = 'b10000;
    
        always_ff @ (posedge aclk)
        begin
            if(~aresetn)
            begin
                axi_w_cs <= WRITE_IDLE;
            end
        
            else
            begin
                axi_w_cs <= axi_w_ns;
            end
        end

        always_comb
        begin
            case(axi_w_cs)
            WRITE_IDLE:
            begin
                if(start_write)  axi_w_ns = WRITE_CHK_CMD;
                else             axi_w_ns = WRITE_IDLE;
            end

            WRITE_CHK_CMD:
            begin
                if(~error_redux_or) axi_w_ns = WRITE_ADDRESS;
                else                axi_w_ns = WRITE_IDLE;
            end
            
            WRITE_ADDRESS:
            begin
                if(m_axi_awready)   axi_w_ns = WRITE;
                else                axi_w_ns = WRITE_ADDRESS;
            end
        
            WRITE:
            begin
                if((w_data_counter == len_w_tmp_ff) && m_axi_wready)
                begin
                    axi_w_ns = WRITE_RESPONSE;
                end
            
                else
                begin
                    axi_w_ns = WRITE;
                end
            end
        
            WRITE_RESPONSE:
            begin
                if(m_axi_bvalid)
                begin
                    if(start_write) axi_w_ns = WRITE_CHK_CMD;
                    else            axi_w_ns = WRITE_IDLE;
                end
                else axi_w_ns = WRITE_RESPONSE;
            end
        
            default: axi_w_ns = WRITE_IDLE;
            endcase
        end

        assign next_w_feed_in       = (((axi_w_cs == WRITE_RESPONSE) && (m_axi_bvalid)) || (axi_w_cs == WRITE_IDLE)) ? 1 : 0;
        assign user_w_free          = (((axi_w_ns == WRITE_RESPONSE) || (axi_w_ns == WRITE_IDLE)) && ~start_w_ff && ~burst_w_split_flag_ff) ? 1 : 0;

        always_comb
        begin
            m_axi_awvalid  = 'h0;
            m_axi_awlen    = 'h0;
            m_axi_awlock   = 'h0;
            m_axi_awqos    = 'h0;
            m_axi_awregion = 'h0;
            m_axi_awaddr   = 'h0;
            m_axi_awprot   = 'h0;
            m_axi_awsize   = 'h0;
            m_axi_awburst  = 'b10;
            m_axi_awcache  = 'h0;
            m_axi_awid     = 'h0;
            m_axi_wvalid   = 'h0;
            m_axi_wdata    = 'h0;
            m_axi_wstrb    = 'h0;
            m_axi_wlast    = 'h0;
            m_axi_bready   = 'h0;
            //user_w_data_pop_req = 'h0;
            user_w_wready = 'h0;
            user_w_bid = 'h0;
            user_w_status = 'h0;
            user_w_bvalid = 'h0;

            if(axi_w_cs==WRITE_ADDRESS)
            begin
                m_axi_awvalid = 'h1;
                m_axi_awlen   = len_w_tmp_ff;
                m_axi_awaddr  = addr_w_tmp_ff;
                m_axi_awsize  = user_w_awsize_ff;
                m_axi_awid    = user_w_awid_ff;
            end

            w_data_final = (MISALIGN_ADJUST==0) ? user_w_data : aligned_w_data_final;
            w_strb_final = (MISALIGN_ADJUST==0) ? user_w_strb : aligned_w_strb_final;

            if(axi_w_cs==WRITE)
            begin
                case(BURST_POLICY)
                    0: 
                    begin
                        m_axi_wvalid  = 1; // data was pre-checked so no need to stall
                        m_axi_wdata   = w_data_final;
                        m_axi_wstrb   = w_strb_final;
                    end
                    
                    1: 
                    begin
                        //m_axi_wvalid  = ~(user_w_data_fifo_empty); // stall and wait if fifo is empty
                        m_axi_wvalid  = user_w_wvalid;
                        m_axi_wdata   = w_data_final;
                        m_axi_wstrb   = w_strb_final;
                    end

                    2: 
                    begin
                        m_axi_wvalid  = 1; // never stall, if fifo is empty then output dummy data
                        m_axi_wdata   = (~(user_w_data_fifo_empty)) ? w_data_final : 'h0;
                        m_axi_wstrb   = (~(user_w_data_fifo_empty)) ? w_strb_final : 'h0;
                    end
                endcase

                m_axi_wlast   = (w_data_counter == len_w_tmp_ff);
                //user_w_data_pop_req = (m_axi_wready && m_axi_wvalid && ~(user_w_data_fifo_empty));
                user_w_wready = m_axi_wready;
            end

            if(axi_w_cs == WRITE_RESPONSE)
            begin
                //m_axi_bready  = 'h1;
                m_axi_bready  = user_w_bready; // from fifo (ack)
                user_w_bvalid = m_axi_bvalid; // to fifo (req)

                user_w_bid    = m_axi_bid;
                user_w_status = m_axi_bresp;
            end
        end

//---- Burst write beat counter for FSM ----//
        always_ff @ (posedge aclk)
        begin
            if(axi_w_cs == WRITE_IDLE || axi_w_cs == WRITE_RESPONSE) w_data_counter <= 'h0;
            
            else if(axi_w_cs == WRITE && m_axi_wready && m_axi_wvalid)//w_data_counter < len_w_tmp_ff)
            begin
                w_data_counter <= w_data_counter + 1'b1;
            end
            
            else w_data_counter <= w_data_counter;
        end

// ---- Underrun flag ---- //
        // All underrun tells us is if there's a time whenever the input fifo was empty during a burst
        always_ff @ (posedge aclk)
        begin
            if(~aresetn)
            begin
                underrun_flag_ff <= 'h0;
            end

            else
            begin
                case(BURST_POLICY)
                0:
                begin
                    underrun_flag_ff <= 'h0;
                end

                1,2:
                begin
                    if(start_w_ff)
                    begin
                        underrun_flag_ff <= 'h0;
                    end

                    else if((axi_w_cs==WRITE) && (user_w_data_fifo_empty) && m_axi_wready && m_axi_wvalid)
                    begin
                        underrun_flag_ff <= 'h1;
                    end
                end
                endcase
            end
        end

        assign user_w_underrun_event = underrun_flag_ff;

// ---- Error Flop set and clr for output port ---- //
        assign user_w_cmd_error     = user_w_cmd_error_ff;

        always_ff @ (posedge aclk)
        begin
            if(~aresetn)
            begin
                user_w_cmd_error_ff <= 'h0;
            end

            else
            begin
                if(start_w_ff)
                begin
                    user_w_cmd_error_ff <= 'h0;
                end

                else if(axi_w_cs==WRITE_CHK_CMD)
                begin
                    user_w_cmd_error_ff <= error_wrap;
                end
            end
        end

// 1. ---- Start + 1-stage pipeline + automatic start for cmd boundary split mechanism ---- //
        assign start_write  = (~error_redux_or) & start_w_ff;

        always_ff @ (posedge aclk)
        begin
            if(~aresetn)
            begin
                ready_w_flag          <= 1;
                start_w_ff            <= 0;

                user_w_len_ff           <= 0;
                user_w_addr_ff          <= 0;
                user_w_awsize_ff        <= 0;
                user_w_awid_ff          <= 0;

                w_addr_offset_ff        <= 'h0;
            end
            
            else
            begin
                if(ready_w_flag)
                begin
                    if((SPLIT_PAGE_BOUNDARY > 0) && burst_w_split_flag_ff)
                    begin
                        ready_w_flag      <= 0;
                        start_w_ff        <= 1;

                    end

                    else if(user_w_start)
                    begin
                        ready_w_flag      <= 0;
                        start_w_ff        <= 1;

                        user_w_len_ff     <= user_w_len;
                        user_w_addr_ff    <= user_w_addr;
                        user_w_awsize_ff  <= user_w_awsize;
                        user_w_awid_ff    <= user_w_awid;

                        w_addr_offset_ff  <= user_w_addr[DATA_W_BYTES_CLOG-1:0];
                    end
                end
                
                else if(next_w_feed_in & start_w_ff)
                begin
                    ready_w_flag      <= 1;
                    start_w_ff        <= 0;
                end
            end
        end

// 2. ---- COMB logic used for basis of error-checking and splitting bursts ----//
        always_comb
        begin
        // misaligned address
            total_bytes = ((user_w_len_ff + 1) << DATA_W_BYTES_CLOG);   // total bytes required in entire burst write
                // ex: total_bytes = ((255 + 1) << 4)
                    // DATA_W_BYTES_CLOG=4 because DATA_W=128 ->  DATA_W_BYTES=128/8=16 -> DATA_W_BYTES_CLOG=clog2(16)=4 because 2^(4) = 16
                // REMEMBER: ((255 + 1) << 4) is equivalent to ((255 + 1) / 16)
            misalign_bytes = user_w_addr_ff[DATA_W_BYTES_CLOG-1:0];     // check if the address aligns with the "beat byte width"
                // ex: misalign_bytes = address[4-1:0] -> DATA_W_BYTES_CLOG is explained above
                    // misalign_bytes = 0x03 for example... because it's 3 off from the previous beat byte boundary (axi has a requirement for the data to be byte-aligned with the beat-width)
            beats_required = ((total_bytes + misalign_bytes) + (DATA_W_BYTES-1)) >> DATA_W_BYTES_CLOG; // how many beats are actually required (taking into account misalignment and rounding up to the nearest whole beat for purposes of division)
                // ex: beats_required = ((4096 bytes + 0x03 bytes) + (16-1) >> 4) = 257
                    
                /* explanation:
                    total_bytes + misalign_bytes
                    → accounts for the “extra bytes” you’ll spill into the next beat if you start misaligned.

                    + (DATA_W_BYTES - 1)
                    → ensures round-up division (ceiling division).

                    >> DATA_W_BYTES_CLOG
                    → divide by bytes-per-beat.*/

        // burst splitting
            // bytes until boundary
            bytes_until_boundary = PAGE_SIZE_BYTES - (user_w_addr_ff[PAGE_SIZE_BYTES_CLOG-1:0]); // finding how many bytes are between the page boundary and the starting address
                // ex: bytes_until_boundary = 4096 - (address[11:0]);
                    // PAGE_SIZE_BYTES = 4096 -> PAGE_SIZE_BYTES_CLOG = clog2(4096) -> 12
            // burst beats until boundary
            beats_until_boundary = ((bytes_until_boundary + misalign_bytes) >> DATA_W_BYTES_CLOG); // converting "bytes_until_boundary" to number of axi beats until page boundary
                // REMEMBER: not rounding up because we want 'worst-case scenario' aka floor division because we do not handle partial beats

        // error detection
            no_beats_fit_flag                   = (beats_until_boundary == 0);
            page_boundary_cross_no_split_flag   = (beats_until_boundary < beats_required);// <- simplified version <- original: (awlen_until_boundary < (beats_required-1));
            insufficient_wdata_flag             = (user_w_data_fifo_cnt < beats_required);
            start_w_addr_misalign_flag          = (misalign_bytes != 0);

            error_wrap = {
                            (MISALIGN_ADJUST == 0) && start_w_addr_misalign_flag, 
                            (BURST_POLICY == 0) && insufficient_wdata_flag, 
                            (SPLIT_PAGE_BOUNDARY == 0) && page_boundary_cross_no_split_flag,
                            no_beats_fit_flag
                        };

            error_redux_or = |error_wrap;
            
        // beats decided
            if(page_boundary_cross_no_split_flag)
            begin
                beats_decided = beats_until_boundary;
            end

            else if(beats_required > MAX_BURST_BEATS)
            begin
                beats_decided = MAX_BURST_BEATS;
            end

            else
            begin
                beats_decided = beats_required;
            end

        // awlen decided
            awlen_decided = beats_decided - (|beats_decided);

        // REMEMBER: difference between awlen and beats is (awlen = beats - 1)

        // awlen split: after first burst, how many beats remain
            if(SPLIT_PAGE_BOUNDARY > 0)
            begin
                if(beats_required > beats_decided) // if beats_decided was set to "beats_until_boundary" or "MAX_BURST_BEATS"
                begin
                    awlen_split = (beats_required - beats_decided) - 1;
                end

                else
                begin
                    awlen_split = 0;
                end
            end

            else
            begin
                awlen_split = 0;
            end
        end

// 3. ---- SEQ logic used for first burst addr + awlen (account for misalignment, max burst beats limit, page boundary) ; gets data from '2. COMB logic'^ ----//
        always_ff @ (posedge aclk)
        begin
            if(~aresetn)
            begin
                addr_w_tmp_ff   <= 'h0;
                len_w_tmp_ff    <= 'h0;

                addr_w_split_tmp_ff     <= 'h0;
                len_w_split_tmp_ff      <= 'h0;
                burst_w_split_flag_ff   <= 'h0;
            end

            else
            begin
                if(next_w_feed_in)
                begin
                    if(~burst_w_split_flag_ff)
                    begin
                        // These go directly to the axi slave
                        addr_w_tmp_ff   <= user_w_addr_ff & ~(DATA_W_BYTES-1);  // automatically aligning the address to the closest previous beat boundary
                        len_w_tmp_ff    <= awlen_decided;

                        if(SPLIT_PAGE_BOUNDARY > 0)
                        begin
                            if(beats_required > beats_decided) // if awlen was split
                            begin
                                // items to be used in the burst after the burst split
                                burst_w_split_flag_ff     <= 1'b1;
                                addr_w_split_tmp_ff       <= user_w_addr_ff + (beats_decided * DATA_W_BYTES) & ~(DATA_W_BYTES-1);  // starting address of starting burst after the split
                                len_w_split_tmp_ff        <= awlen_split; // awlen after the split
                            end

                            else
                            begin
                                burst_w_split_flag_ff   <= 1'b0;
                                addr_w_split_tmp_ff     <= 'h0;
                                len_w_split_tmp_ff      <= 'h0;
                            end
                        end

                        else
                        begin
                            burst_w_split_flag_ff   <= 1'b0;
                        end
                    end

                    else
                    begin
                        addr_w_tmp_ff   <= addr_w_split_tmp_ff;
                        len_w_tmp_ff    <= len_w_split_tmp_ff;

                        if(start_w_ff)
                        begin
                            burst_w_split_flag_ff   <= 1'b0;
                        end
                    end
                end
            end
        end

// 4. ---- Misaligned Address ---- //
    // if address is not byte aligned with the beat size then we must align the starting address and therefore change each beat of the burst...

        // COMB logic to calculate aligned shift left and carry shift right (this happens once ber burst)
        always_comb
        begin
            // shift amount for aligned data in current beat
            w_data_shift_left = (w_addr_offset_ff * BYTE);
            w_strb_shift_left = (w_addr_offset_ff);

            // shift amount for carry data to be used in next beat
            w_data_shift_right = (DATA_W - w_data_shift_left);
            w_strb_shift_right = (DATA_W_BYTES - w_strb_shift_left);
            
            // no misalignment, don't edit the data
            if(w_addr_offset_ff == 0)
            begin
                aligned_w_data  =  user_w_data;
                aligned_w_strb  =  user_w_strb;

                carry_w_data    =  'h0;
                carry_w_strb    =  'h0;
            end

            else
            begin   
                // aligned signal is shifted left because if address is misaligned then there are address bytes in the beginning that we aren't trying to write to
                aligned_w_data  =  (user_w_data << (w_data_shift_left));
                aligned_w_strb  =  (user_w_strb << (w_strb_shift_left));

                // carry signal is shifted right because if aligned signals are shifted then we lose the MSB for that beat, so we have to 'carry' it to the next beat or even burst
                carry_w_data    =  (user_w_data >> (w_data_shift_right));
                carry_w_strb    =  (user_w_strb >> (w_strb_shift_right));
            end
        end

        // ALGINER: SEQ logic to flop carry data + w_strb LSB to next burst beat
        always_ff @(posedge aclk) 
        begin
            if (~aresetn) 
            begin
                align_carry_valid_ff <= 1'b0;   // signal checks to see if there is any valid data
                align_carry_w_data_ff <= '0;    // LSB data to be carried to next beat in misaligned burst
                align_carry_w_strb_ff <= '0;    // LSB w_strb to be carried to next beat in misaligned burst
            end

            // if (SPLIT_PAGE_BOUNDARY > 0), the starting address is misaligned, and the burst is split (either from page boundary or exceeds MAX_BURST_BEATS) 
            // then we need to insert the carry data + wstrb of the last beat into the first beat of the next burst created in the split burst
            else if (start_w_ff && burst_w_split_flag_ff) 
            begin
                align_carry_valid_ff <= split_carry_valid_ff;
                align_carry_w_data_ff <= split_carry_w_data_ff;
                align_carry_w_strb_ff <= split_carry_w_strb_ff;
            end

            // restart at start of write burst (carry data is flopped into every beat after the first beat of a burst)
            else if (start_w_ff && ~burst_w_split_flag_ff) 
            begin
                align_carry_valid_ff <= 1'b0;
                align_carry_w_data_ff <= '0;
                align_carry_w_strb_ff <= '0;
            end

            // flopping carry data + w_strb LSB for next beat in the burst
            else if (axi_w_cs==WRITE && m_axi_wready && m_axi_wvalid) 
            begin
                align_carry_valid_ff <= (|carry_w_strb);
                align_carry_w_data_ff <= carry_w_data;
                align_carry_w_strb_ff <= carry_w_strb;
            end
        end

        // SPLITTER: SEQ logic to flop the carry data + w_strb of the last beat in a split burst to be used in the first beat of the next burst
        always_ff @(posedge aclk) 
        begin
            if (~aresetn) 
            begin
                split_carry_valid_ff <= 1'b0;   // signal checks to see if there is any valid data
                split_carry_w_data_ff <= '0;    // LSB data to be carried to first beat of next burst in split burst
                split_carry_w_strb_ff <= '0;    // LSB w_strb to be carried to first beat of next burst in split burst
            end

            // if (SPLIT_PAGE_BOUNDARY > 0), the starting address is misaligned, and the burst is split (either from page boundary or exceeds MAX_BURST_BEATS),
            // then flop the LSB data + wstrb of the last beat of the current burst
            else if ((axi_w_cs == WRITE) && m_axi_wvalid && m_axi_wready && m_axi_wlast && burst_w_split_flag_ff) 
            begin
                split_carry_valid_ff <= |carry_w_strb;
                split_carry_w_data_ff <= carry_w_data;
                split_carry_w_strb_ff <= carry_w_strb;
            end

            // inactive if burst split flag is not set
            else if (start_w_ff && ~burst_w_split_flag_ff) 
            begin
                split_carry_valid_ff <= 'h0;
                split_carry_w_data_ff <= 'h0;
                split_carry_w_strb_ff <= 'h0;
            end
        end

        // OUT TO AXI WRITE PORT: COMB logic to do (<aligned data current shifted left [LSB shifted left]> | <aligned carry data previous beat shifted right [MSB shifted right]>)
        always_comb
        begin
            aligned_w_data_final = 'h0;
            aligned_w_strb_final = 'h0;

            aligned_w_data_final = ((align_carry_valid_ff) ? align_carry_w_data_ff : 'h0)| aligned_w_data;
            aligned_w_strb_final = ((align_carry_valid_ff) ? align_carry_w_strb_ff : 'h0)| aligned_w_strb;
        end
    end
endgenerate

endmodule
        /* example:
        Parameters:
            DATA_W_BYTES = 16 (128-bit)
            PAGE_SIZE_BYTES = 4096
            user_w_addr_ff = 0x0FF4 (offset 0xF4 decimal 244 into page) — misaligned
            user_w_len = 1 (AWLEN=1 => user asked for 2 beats of data i.e. 2 * 16 = 32 bytes)

        Compute:
            misalign_bytes = 244
            total_bytes = (1 + 1) * 16 = 32
            beats_required = ceil((32 + 244) /16) = ceil(276/16) = 18 beats
            bytes_until_boundary = 4096 - (0x0FF4 & 4095) = 4096 - 4084 = 12 bytes
            beats_until_boundary = 12 >> 4 = 0 (no full beats fit before page boundary)
            page_boundary_cross_no_split_flag = (0 < 18) => true -> needs split
            beats_decided = beats_until_boundary = 0

            -> no_beats_fit flag would incur an error...
        */

    /*
    ---- Misaligned Address Components ---- // also handles misalignment after burst split too
    1. start mechanism
        - if(user_w_start) flop in the awlen, addr, and address misalignment -> go to 2
        - if(burst split flag) in previous burst (in 3.) -> go to 3
    2. combo detecting:
        - address misalignment
        - burst splitting requirement
        - error detection
        - beats, awlen, and awlen split (second burst) decided
        - go to 3
    3. flop:
        - if not (burst split flag) flop address (auto align to beat byte boundary) + awlen
            - if required split was detected in 2. then flop the burst split flag, first address after split, and awlen after split
        - if(burst split flag) flop address + awlen from when burst split was detected in the ^ immediate line above
            - this ^ would happen at the beginning of second burst in burst split
    4. dealing with address misalignment
        - data shifting:
            - comb logic:
                - finds the left + right shift amount and calculates the aligned data + carry data
            - aligner:
                - if(misaligned address) carry data + wstrb from current beat is flopped to be used in the next beat sent to axi slave
            - splitter:
                - if(burst split flag) carry data + wstrb from last beat of current burst is flopped to be used in the first beat of the next burst created because of split burst
            - last comb logic:
                - data sent to axi write port  = ((first beat) ? 0 : carry data from previous beat) | (aligned data from current beat)

        - explanation
            - if the starting address is misaligned then every single input data beat needs to be split to account for this misalignment (because each burst beat must be beat-byte aligned)
            - for example, if the starting address is misaligned by 4 bytes then we need to adjust each data beat accordingly:
                - data in = 0x1111_0001_0100_0110
                    - address was shifted right by 4 bytes... which means we need to shift each data in + wstrb by one byte... but remember the first byte does not contain valid writing territory... but we can't lose the top portition of the input beat so we need to carry that to the next beat
                    --> to deal with address shift due to misalignment: data in becomes: 0x1111_0001_0100_0110 << (4 byte) = 0x0100_0110_0000_0000
                        - why right shift? : because when address is shifted right to meet the beat-byte alignment, the extra addresses added to the burst are not part of the desired write territory. Therefore, we have to shift the data-in in the opposite direction (left) to compensate for these extra undesired addresses being added to the burst
                    --> BUT we don't want to lose the top portion of this beat so it becomes the carry which is flopped in as the LSB of the next beat -> carry = 0x1111_0001
                
            - example extended:
                - misalignment amount was 4 bytes
                - 1. first beat: data in = 0x1111_0001_0100_0110
                    - carry from previous beat = 0x0 (first beat that's not after a split)

                    - aligned data = (data in) << 4 bytes = 0x0100_0110_0000_0000
                    - carry data for next beat = (data in) >> 4 bytes = 0x1111_0001

                    --> <data to axi port = 0x0100_0110_0000_0000>
                - 2. data in = 0x1010_1111_1100_0011
                    - carry from previous beat = 0x1111_0001

                    - aligned data = (data in) << 4 bytes = 0x1100_0011_0000_0000
                    - carry data for next beat = (data in) >> 4 bytes = 0x1010_1111
                    
                    --> <data to axi port = (aligned data current beat shift left) | (carry data previous beat shifted right)  = (0x1100_0011_0000_0000) | (0x1111_0001) = 0x1100_0011_1111_0001> 

                ....
    */
