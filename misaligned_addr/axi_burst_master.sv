
// SIGNALS NOT CURRENTLY USED:
    // AXI-ID   : ARID->RID, AWID->BID , identifies transaction so responses can be matched to the requester. This is for if a master allows queuing of multiple outstanding bursts
    // LOCK     : AWLOCK/ARLOCK , locked transactions (exclusive)
    // QOS      : AWQOS/ARQOS , priority hint for arbiter
    // REGION   : AWREGION/ARREGION , extra routing bits for complex interconnects
    // CACHE + PROT , cacheability and protection hints, usually for DMA/master

// FUTURE REQUIREMENTS
    // command fifo: {awid, awaddr, awlen, awsize, awburst, awprot, awcache, awqos, awregion}
    // data fifo: {wdata, wstrb}
    // resp fifo: {bresp, bid}

    // misaligned addr adjustment
    // narrow burst: yes, if someone changes AWSIZE at somepoint then keep the data_w size the same and just use write strobe accordingly

module axi_burst_master #(
    parameter AXI_VER=0, // 4 = AXI4, else = AXI3
    parameter ADDR_W=32,
    parameter DATA_W=64,
    parameter WRITE_EN=1,
    parameter READ_EN=1,
    parameter PAGE_SIZE_BYTES=4096,
    parameter SPLIT_PAGE_BOUNDARY=1, // 0: end burst at page boundary, >0: split burst at page boundary
    parameter BURST_POLICY=0, // 0: (safe) require full burst upfront, 1: stream, wait until data is present by lowering wvalid, 2: pad with dummy data if fifo empty
    parameter MISALIGN_ADJUST=0 // 0: disallow (results in error), >0: allow
    //parameter NARROW_BURST=0 // 0: disallow (results in error), >0: allow
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
    user_w_start,
    user_w_len,
    user_w_addr,
    user_w_status,
    user_w_free,
    user_w_cmd_error,
    user_w_strb,
    user_w_data,
    user_w_fifo_cnt,
    user_w_fifo_empty,
    user_w_data_pop_req,
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

// GENERAL
    localparam BYTE = 8;
    localparam PAGE_SIZE_BYTES_CLOG = $clog2(PAGE_SIZE_BYTES);
    localparam DATA_W_CLOG = $clog2(DATA_W);
    localparam DATA_W_BYTES = DATA_W/BYTE;
    localparam DATA_W_BYTES_CLOG = $clog2(DATA_W_BYTES);
    localparam STRB_W_CLOG = $clog2(DATA_W_BYTES);

// AXI
    localparam LEN_W            = (AXI_VER == 4) ? 8 : 4;
    localparam LOCK_W           = (AXI_VER == 4) ? 1 : 2;
    localparam STRB_W           = DATA_W_BYTES;
    localparam QOS_W            = 4;
    localparam CACHE_W          = 4;
    localparam ABURST_W         = 2;
    localparam ASIZE_W          = DATA_W_BYTES_CLOG;
    localparam PROT_W           = 3;
    localparam RESP_W           = 2;
    localparam REGION_W         = 4;
    localparam ID_W             = 0;
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
    //write
    input  wire                                 user_w_start;
    input  wire [LEN_W-1:0]                     user_w_len;
    input  wire [ADDR_W-1:0]                    user_w_addr;
    output wire [RESP_W-1:0]                    user_w_status; // 00:OKAY, 01:EXOKAY, 10:SLVERR, 11:DECERR
    output wire                                 user_w_free;
    output wire [3:0]                           user_w_cmd_error; // 00:OKAY, 01:NOROOM (1 beat can't fit before next page boundary), 
    output wire                                 user_w_underrun_event;
    //write data
    input  wire [STRB_W-1:0]                    user_w_strb;
    input  wire [DATA_W-1:0]                    user_w_data;
    input  wire [LEN_W-1:0]                     user_w_fifo_cnt;
    input  wire                                 user_w_fifo_empty;
    output wire                                 user_w_data_pop_req;

    //read
    input  wire                                 user_r_start;
    input  wire [LEN_W-1:0]                     user_r_len;
    input  wire [ADDR_W-1:0]                    user_r_addr;
    output wire [RESP_W-1:0]                    user_r_status;
    output wire                                 user_r_free;
    //read data
    output wire [DATA_W-1:0]                    user_r_data;
    input  wire [LEN_W-1:0]                     user_r_fifo_cnt;
    input  wire                                 user_r_fifo_full;
    output reg                                  user_r_data_push_req;
/*******************************************************/

// AXI W ---------------------------------------------------
generate
    if(WRITE_EN)
    begin

        logic                   start_write;
        reg [4:0]               axi_w_cs, axi_w_ns;
        reg [LEN_W-1:0]         w_data_counter;
        reg [LEN_W-1:0]         user_w_len_ff;
        reg [ADDR_W-1:0]        user_w_addr_ff;
        reg                     ready_w_flag;
        reg                     start_w_ff;
        wire                    next_w_feed_in;
        logic                   burst_w_split_flag_ff;
        logic                   misalign_w_addr_flag_ff;
        logic [ADDR_W-1:0]      addr_w_tmp_ff;
        logic [LEN_W-1:0]       len_w_tmp_ff;
        logic [ADDR_W-1:0]      addr_w_split_tmp_ff;
        logic [LEN_W-1:0]       len_w_split_tmp_ff;
        logic [ADDR_W-1:0]      bytes_until_boundary;
        logic [LEN_W-1:0]       beats_until_boundary;
        logic [LEN_W-1:0]       awlen_until_boundary;
        logic [3:0]             error_wrap;
        logic                   error_redux_or;
        wire                    no_beats_fit_flag;
        wire                    page_boundary_cross_no_split_flag;
        wire                    insufficient_wdata_flag;
        wire                    start_w_addr_misalign_flag;
        logic [3:0]             user_w_cmd_error_ff;
        logic                   underrun_flag_ff;

        wire [DATA_W-1:0]       w_data_final;
        wire [STRB_W-1:0]       w_strb_final; 
        
        // Misaligned Address
        wire [ADDR_W-1:0]               w_addr_aligned;
        wire [DATA_W_BYTES_CLOG-1:0]    w_addr_offset;
        
        
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
            m_axi_awvalid = 'h0;
            m_axi_awlen   = 'h0;
            m_axi_awaddr  = 'h0;
            m_axi_wvalid  = 'h0;
            m_axi_wdata   = 'h0;
            m_axi_wstrb   = 'h0;
            m_axi_wlast   = 'h0;
            m_axi_bready  = 'h0;
            user_w_data_pop_req = 'h0;

            if(axi_w_cs==WRITE_ADDRESS)
            begin
                m_axi_awvalid = 'h1;
                m_axi_awlen   = len_w_tmp_ff;
                m_axi_awaddr  = addr_w_tmp_ff;
            end

            w_data_final = (MISALIGN_ADJUST==0) ? user_w_data : /*<aligned data here>*/;
            w_strb_final = (MISALIGN_ADJUST==0) ? user_w_strb : /*<aligned wstrb here>*/;

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
                        m_axi_wvalid  = ~(user_w_fifo_empty); // stall and wait if fifo is empty
                        m_axi_wdata   = w_data_final;
                        m_axi_wstrb   = w_strb_final;
                    end

                    2: 
                    begin
                        m_axi_wvalid  = 1; // never stall, if fifo is empty then output dummy data
                        m_axi_wdata   = (~(user_w_fifo_empty)) ? w_data_final : 'h0;
                        m_axi_wstrb   = (~(user_w_fifo_empty)) ? w_strb_final : 'h0;
                    end
                endcase

                m_axi_wlast   = (w_data_counter == len_w_tmp_ff);
                user_w_data_pop_req = (m_axi_wready && m_axi_wvalid && ~(user_w_fifo_empty));
            end

            if(axi_w_cs == WRITE_RESPONSE)
            begin
                m_axi_bready  = 'h1;
            end
        end

// ---- Misaligned Address ---- //
    // TODO
    reg  [DATA_W_BYTES_CLOG-1:0]    w_addr_offset_ff;

    reg carry_valid_ff;
    reg [DATA_W-1:0] carry_w_data_ff;
    reg [STRB_W-1:0] carry_w_strb_ff;

    wire [DATA_W-1:0] aligned_w_data;
    wire [DATA_W-1:0] carry_w_data;
    wire [DATA_W-1:0] aligned_w_data_final;
    wire [STRB_W-1:0] aligned_w_strb;
    wire [STRB_W-1:0] carry_w_strb;
    wire [STRB_W-1:0] aligned_w_strb_final;

    wire [DATA_W_CLOG-1:0] w_data_shift_left;
    wire [DATA_W_CLOG-1:0] w_data_shift_right;

    wire [STRB_W_CLOG-1:0] w_strb_shift_left;
    wire [STRB_W_CLOG-1:0] w_strb_shift_right;

    // Requirement:
        // - sequential logic for holding carry out data
            // carry valid (check wstrb bits)
            // carry data AND strb (flop the right-shifted signals for use in the next beat)
        // - combinational logic for w_data input shifting
            // shift data AND strb left (this becomes the data to use)
            // shift data AND strb right (this becomes the carry out)

            // aligned data + strb out that goes to the axi signals

    // EX:
        // 1. find the address offset + increase len -> len + 1
            // - detect if split burst is required (cross page boundary and/or len+1 > MAX_BURST_LEN)
        // 2. use the address offset to calculate:
            // - carry_out = (write data >> (address offset*8))
            // - data_to_use = (write data << (address offset*8))
        // 3. flop the carry out + write "data_to_use" to the w_data axi signal
            // flop : carry_out_ff <= carry_out
            // comb : m_axi_wdata = carry_out_ff | data_to_use;
        // 4. wlast
            // -> if split burst then we are required to carry data + wstrb  over to the next burst
            // -> if not:
                // comb : m_axi_wdata = carry_out_ff | 'h0;

        always_comb
        begin
            w_data_shift_left = (w_addr_offset_ff * BYTE);
            w_data_shift_right = (DATA_W - w_data_shift_left);

            w_strb_shift_left = (w_addr_offset_ff);
            w_strb_shift_right = (DATA_W_BYTES - w_strb_shift_left);

            if(w_addr_offset_ff == 0)
            begin
                aligned_w_data  =  user_w_data;
                carry_w_data    =  'h0;
                aligned_w_strb  =  user_w_strb;
                carry_w_strb    =  'h0;
            end

            else
            begin
                aligned_w_data  =  (user_w_data << (w_data_shift_left));
                carry_w_data    =  (user_w_data >> (w_data_shift_right));

                aligned_w_strb  =  (user_w_strb << (w_strb_shift_left));
                carry_w_strb    =  (user_w_strb >> (w_strb_shift_right));
            end
        end

// aligner
        always_ff @(posedge aclk) 
        begin
        if (~aresetn) 
        begin
            align_carry_valid_ff <= 1'b0;
            align_carry_w_data_ff <= '0;
            align_carry_w_strb_ff <= '0;
        end

        else if (axi_w_cs==WRITE && m_axi_wready && m_axi_wvalid) 
        begin
            align_carry_valid_ff <= (|carry_w_strb);  // your shifted_lo leftover
            align_carry_w_data_ff <= carry_w_data;    // low bits that didn’t fit
            align_carry_w_strb_ff <= carry_w_strb;
        end

        else if (start_w_ff && ~split_carry_valid_ff) 
        begin
            align_carry_valid_ff <= 1'b0;  // reset at burst start
            align_carry_w_data_ff <= '0;
            align_carry_w_strb_ff <= '0;
        end

        else if (start_w_ff && split_carry_valid_ff) 
        begin
            align_carry_valid_ff <= split_carry_valid_ff;  // burst start after split
            align_carry_w_data_ff <= split_carry_w_data_ff;
            align_carry_w_strb_ff <= split_carry_w_strb_ff;
        end
    end

// splitter
        always_ff @(posedge aclk) 
        begin
            if (~aresetn) 
            begin
                split_carry_valid_ff <= 1'b0;
                split_carry_w_data_ff <= '0;
                split_carry_w_strb_ff <= '0;
            end

            else if ((axi_w_cs == WRITE) && m_axi_wvalid && m_axi_wready && m_axi_wlast && burst_w_split_flag_ff) 
            begin
                // ISSUE: i don't think this is correct; we only need to carry over the "carry data" to the next split...
                split_carry_valid_ff <= |carry_w_strb;
                split_carry_w_data_ff <= carry_w_data;
                split_carry_w_strb_ff <= carry_w_strb;
            end

            else if (start_w_ff) 
            begin
                split_carry_valid_ff <= split_carry_valid_ff;
            end
        end

        always_comb
        begin
            aligned_w_data_final = 'h0;
            aligned_w_strb_final = 'h0;

            aligned_w_data_final = ((carry_valid_ff) ? carry_w_data_ff : 'h0)| aligned_w_data;
            aligned_w_strb_final = ((carry_valid_ff) ? carry_w_strb_ff : 'h0)| aligned_w_strb;

            // need to save the 'carry_w_data_ff' and 'carry_w_strb_ff' if 'burst_w_split_flag_ff' flag is set
        end

// ---- Underrun flag ---- //
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

                    else if((axi_w_cs==WRITE) && (user_w_fifo_empty) && m_axi_wready && m_axi_wvalid)
                    begin
                        underrun_flag_ff <= 'h1;
                    end
                end
                endcase
            end
        end

        assign user_w_underrun_event = underrun_flag_ff;

// ---- Start + 1-stage pipeline + automatic start for cmd boundary split mechanism ---- //
        assign start_write  = (~error_redux_or) & start_w_ff;

        always_ff @ (posedge aclk)
        begin
            if(~aresetn)
            begin
                ready_w_flag          <= 1;
                start_w_ff            <= 0;

                user_w_len_ff           <= 0;
                user_w_addr_ff          <= 0;
            end
            
            else
            begin
                if(ready_w_flag)
                begin
                    // TODO: misaligned address causes a split burst (1. across boundary, 2. len+1 > MAX_BURST_LEN, 3. both)

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
                    end
                end
                
                else if(next_w_feed_in & start_w_ff)
                begin
                    ready_w_flag      <= 1;
                    start_w_ff        <= 0;
                end
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

//---- Write status flop ----//
        assign user_w_status = user_w_status_ff;

        always_ff (posedge aclk)
        begin
            if(~aresetn)
            begin
                user_w_status_ff  <= 'h0;
            end

            else 
            begin
                if(start_w_ff)
                begin
                    user_w_status_ff  <= 'h0;
                end

                if(m_axi_bready && m_axi_bvalid)
                begin
                    user_w_status_ff  <= m_axi_bresp;
                end
            end
        end

//---- COMB + SEQ logic used for basis of error-checking and splitting bursts ----//
        always_comb
        begin
        // misaligned address
            total_bytes = ((user_w_len_ff + 1) << DATA_W_BYTES_CLOG);
            misalign_bytes = user_w_addr_ff[DATA_W_BYTES_CLOG-1:0]
            beats_required = ((total_bytes + misalign_bytes) + (DATA_W_BYTES-1)) >> DATA_W_BYTES_CLOG;

        // burst splitting
            // bytes until boundary
            bytes_until_boundary = PAGE_SIZE_BYTES - (user_w_addr_ff[PAGE_SIZE_BYTES_CLOG-1:0]);
            // burst beats until boundary
            beats_until_boundary = (bytes_until_boundary >> DATA_W_BYTES_CLOG);
            // adjusted for awlen (len-1)
            awlen_until_boundary = (beats_until_boundary == 0) ? 0 : beats_until_boundary-1;

        // error detection
            no_beats_fit_flag                   = (beats_until_boundary == 0);
            page_boundary_cross_no_split_flag   = (awlen_until_boundary < user_w_len_ff);
            insufficient_wdata_flag             = (user_w_fifo_cnt < user_w_len_ff+1);
            start_w_addr_misalign_flag          = (misalign_bytes != 0);

            error_wrap = {
                            (MISALIGN_ADJUST == 0) && start_w_addr_misalign_flag, 
                            (WRITE_SAFE_MODE > 0) && insufficient_wdata_flag, 
                            (SPLIT_PAGE_BOUNDARY == 0) && page_boundary_cross_no_split_flag, 
                            no_beats_fit_flag
                        };

            error_redux_or = |error_wrap;

        // len decision
            len_decided = (page_boundary_cross_no_split_flag) ? awlen_until_boundary : ((beats_required > (MAX_BURST_BEATS-1)) ? MAX_BURST_BEATS-1 : user_w_len_ff);
        end

        always_ff @ (posedge aclk)
        begin
            if(~aresetn)
            begin
                addr_w_tmp_ff   <= 'h0;
                len_w_tmp_ff    <= 'h0;

                addr_w_split_tmp_ff     <= 'h0;
                len_w_split_tmp_ff      <= 'h0;
                burst_w_split_flag_ff   <= 'h0;

                misalign_w_addr_flag_ff <= 'h0;
            end

            else
            begin
                if(next_w_feed_in)
                begin
                    if(~burst_w_split_flag_ff)
                    begin

                        addr_w_tmp_ff   <= user_w_addr_ff & ~(DATA_W_BYTES-1);
                        len_w_tmp_ff    <= len_decided - 1;

                        if(SPLIT_PAGE_BOUNDARY > 0)
                        begin
                            if(beats_required > len_decided)
                            begin
                                burst_w_split_flag_ff     <= 1'b1;
                                addr_w_split_tmp_ff       <= user_w_addr_ff + (len_decided * DATA_W_BYTES) - misalign_bytes;
                                len_w_split_tmp_ff        <= (beats_required - len_decided) - 1;
                            end

                            else
                            begin
                                burst_w_split_flag_ff   <= 1'b0;
                                addr_w_split_tmp_ff     <= 'h0;
                                len_w_split_tmp_ff      <= 'h0;
                            end
                        end
                    end

                    else
                    begin
                        addr_w_tmp_ff   <= addr_w_split_tmp_ff;
                        len_w_tmp_ff    <= len_w_split_tmp_ff;
                    end
                end
            end
        end

// ---- Error Flop set and clr for output port ----//
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
    end
endgenerate

// AXI R ---------------------------------------------------
generate
    if(READ_EN)
    begin
        // FSM
        localparam READ_IDLE       = 5'b00001;
        localparam READ_ADDRESS    = 5'b00010;
        localparam READ_RESPONSE   = 5'b00100;

        logic start_read;
        
        reg [5:0] axi_r_cs, axi_r_ns;
    
        always @ (posedge aclk)
        begin
            if(~aresetn)
            begin
                axi_r_cs <= READ_IDLE;
            end
        
            else
            begin
                axi_r_cs <= axi_r_ns;
            end
        end

        always @ (*)
        begin
            case(axi_r_cs)
            READ_IDLE:
            begin
                if(start_read)  axi_r_ns = READ_ADDRESS;
                else            axi_r_ns = READ_IDLE;
            end
            
            READ_ADDRESS:
            begin
                if(m_axi_arready)  axi_r_ns = READ_RESPONSE;
                else               axi_r_ns = READ_ADDRESS;
            end

            READ_RESPONSE:
            begin
                if(m_axi_rlast)
                begin
                    if(start_read)  axi_r_ns = READ_ADDRESS;
                    else            axi_r_ns = READ_IDLE;
                end
            
                else
                begin
                    axi_r_ns = READ_RESPONSE;
                end
            end
        
            default: axi_r_ns = READ_IDLE;
            endcase
        end

        // System for locking-in next operation via flops
        reg [8-1:0]                 user_r_len_ff;
        reg [ADDR_W-1:0]            user_r_addr_ff;
        
        reg                         ready_r_flag;
        reg                         start_r_ff;
        wire                        next_r_feed_in;

        assign start_read = start_r_ff;

        always @ (posedge aclk)
        begin
            if(~aresetn)
            begin
                ready_r_flag            <= 1;
                start_r_ff              <= 0;
                //
                user_r_len_ff           <= 0;
                user_r_addr_ff          <= 0;
            end
            
            else
            begin
                if(ready_r_flag & user_r_start)
                begin
                    ready_flag      <= 0;
                    start_ff        <= 1;
                    //
                    user_r_len_ff     <= user_r_len;
                    user_r_addr_ff    <= user_r_addr;
                end
                
                else if(next_r_feed_in & start_r_ff)
                begin
                    ready_r_flag      <= 1;
                    start_r_ff        <= 0;
                end
            end
        end
        
        assign next_r_feed_in        = (((axi_r_cs == READ_RESPONSE) && (m_axi_rlast)) || (axi_r_cs == READ_IDLE)) ? 1 : 0;
        assign user_r_free           = (((axi_r_ns == READ_RESPONSE) || (axi_r_ns == READ_IDLE)) && ~start_r_ff) ? 1 : 0;
        // System for locking-in next operation via flops ^^^

        // AXI IN/OUT Signals
        always @ (posedge aclk)
        begin
            if(~aresetn)
            begin
                user_r_status_ff   <= 0;
            end
            
            else if(m_axi_rready && m_axi_rvalid)
            begin
                user_r_status_ff   <= m_axi_rresp;
            end

            else
            begin
                user_r_status_ff   <= 0;
            end
        end

        assign user_r_status         = user_r_status_ff;  

        always_comb
        begin
            m_axi_arvalid   = 'h0;
            m_axi_arlen     = 'h0;
            m_axi_araddr    = 'h0;
            m_axi_rready    = 'h0;
            user_r_data     = 'h0;
            user_r_data_push_req = 'h0;

            if(axi_r_cs==READ_ADDRESS)
            begin
                m_axi_araddr      = user_addr_in_ff;
                m_axi_arlen       = user_r_len_ff;
                m_axi_arvalid     = 'h1;
            end
            
            if(axi_r_cs==READ_RESPONSE)
            begin
                m_axi_rready      = ~(user_r_fifo_full);
                user_r_data       = m_axi_rdata;
                user_r_data_push_req    = m_axi_rvalid && m_axi_rready;
            end
        end
    end
endgenerate
endmodule
