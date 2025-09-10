
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
    // narrow burst?

module axi_burst_master #(
    parameter AXI_VER=0, // 4 = AXI4, else = AXI3
    parameter ADDR_W=32,
    parameter DATA_W=64,
    parameter WRITE_EN=1,
    parameter READ_EN=1,
    parameter PAGE_SIZE_BYTES=4096,
    parameter SPLIT_PAGE_BOUNDARY=1, // 0: end burst at page boundary, >0: split burst at page boundary
    parameter WRITE_DATA_POLICY=1, // 0: (safe) require full burst upfront, 1: stream, wait until data is present by lowering wvalid, 2: pad with dummy data if fifo empty
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
// AXI
    localparam LEN_W    = (AXI_VER == 4) ? 8 : 4;
    localparam LOCK_W   = (AXI_VER == 4) ? 1 : 2;
    localparam STRB_W   = DATA_W/8;
    localparam QOS_W    = 4;
    localparam CACHE_W  = 4;
    localparam ABURST_W = 2;
    localparam ASIZE_W  = $clog2(DATA_W/8);
    localparam PROT_W   = 3;
    localparam RESP_W   = 2;
    localparam REGION_W = 4;
    localparam ID_W     = 0;

// GENERAL

    localparam PAGE_SIZE_BITS = $clog2(PAGE_SIZE_BYTES);
    localparam DATA_W_BYTES = DATA_W/8;

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
    output reg [DATA_W_BYTES-1:0]       m_axi_wstrb;     //
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

        logic               start_write;
        reg [4:0]           axi_w_cs, axi_w_ns;
        reg [LEN_W-1:0]     w_data_counter;
        reg [LEN_W-1:0]     user_w_len_ff;
        reg [ADDR_W-1:0]    user_w_addr_ff;
        reg                 ready_w_flag;
        reg                 start_w_ff;
        wire                next_w_feed_in;
        logic               burst_w_split_flag_ff;
        logic [ADDR_W-1:0]  addr_w_tmp_ff;
        logic [LEN_W-1:0]   len_w_tmp_ff;
        logic [ADDR_W-1:0]  addr_w_split_tmp_ff;
        logic [LEN_W-1:0]   len_w_split_tmp_ff;
        logic [ADDR_W-1:0]  bytes_until_boundary;
        logic [LEN_W-1:0]   beats_until_boundary;
        logic [3:0]         error_wrap;
        logic               error_redux_or;
        wire                no_beats_fit_flag;
        wire                page_boundary_cross_no_split_flag;
        wire                insufficient_wdata_flag;
        wire                start_addr_unaligned_flag;
        logic [3:0]         user_w_cmd_error_ff;
        
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
                if(~error_redux_or)         axi_w_ns = WRITE_ADDRESS;
                else                        axi_w_ns = WRITE_IDLE;
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

            if(axi_w_cs==WRITE)
            begin
                case(WRITE_DATA_POLICY)
                    0:  m_axi_wvalid  = 1; // data was pre-checked so no need to stall
                    1:  m_axi_wvalid  = ~(user_w_fifo_empty); // stall and wait if fifo is empty
                    2:  m_axi_wvalid  = 1; // never stall, if fifo is empty then output dummy data
                endcase
                m_axi_wdata   = user_w_data;
                m_axi_wstrb   = user_w_strb;
                m_axi_wlast   = (w_data_counter == len_w_tmp_ff);
                user_w_data_pop_req = m_axi_wready;
            end

            if(axi_w_cs == WRITE_RESPONSE)
            begin
                m_axi_bready  = 'h1;
            end
        end

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
            
            else if(axi_w_cs == WRITE && m_axi_wready && w_data_counter < len_w_tmp_ff)
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
            // bytes until boundary
            bytes_until_boundary = PAGE_SIZE_BYTES - (user_w_addr_ff[PAGE_SIZE_BITS-1:0]);
            
            // axi burst beats until boundary
                // = (bytes until boundary) / 2^($clog2(DATA_W_BYTES)) ; where DATA_W must be a whole number and a factor of 2^N
                    // -> NOTE: DATA_W is the width of a burst beat in bits
                    // -> DATA_W_BYTES = DATA_W/8
                    // -> $clog2(DATA_W_BYTES) is the number of bits in DATA_W_BYTES ; we need this to emulate division with shifting
                // This equation explained: (beats until boundary) = (bytes until boundary) / (bytes in a burst beat) 
            beats_until_boundary = (bytes_until_boundary >> $clog2(DATA_W_BYTES));

            no_beats_fit_flag                   = (beats_until_boundary == 0);
            page_boundary_cross_no_split_flag   = ((SPLIT_PAGE_BOUNDARY == 0) && (beats_until_boundary < user_w_len_ff+1));
            insufficient_wdata_flag             = (WRITE_SAFE_MODE > 0) ? (user_w_fifo_cnt < user_w_len_ff+1) : 1'b0;
            start_addr_unaligned_flag           = ((user_w_addr_ff & DATA_W_BYTES-1) != 0);

            error_wrap = {start_addr_unaligned_flag, insufficient_wdata_flag, page_boundary_cross_no_split_flag, no_beats_fit_flag};
            error_redux_or = |error_wrap;
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
            end

            else
            begin
                if(SPLIT_PAGE_BOUNDARY > 0)
                begin
                    if(next_w_feed_in)
                    begin
                        if(~burst_w_split_flag_ff)
                        begin
                            addr_w_tmp_ff   <= user_w_addr_ff;
                            len_w_tmp_ff    <= min(beats_until_boundary, user_w_len_ff+1);

                            if(user_w_len_ff > beats_until_boundary)
                            begin
                                burst_w_split_flag_ff     <= 1'b1;
                                addr_w_split_tmp_ff       <= user_w_addr_ff + bytes_until_boundary;
                                len_w_split_tmp_ff        <= user_w_len_ff - beats_until_boundary;
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
                            addr_w_tmp_ff   <= addr_w_split_tmp_ff;
                            len_w_tmp_ff    <= len_w_split_tmp_ff;

                            if(start_w_ff)
                            begin
                                burst_w_split_flag_ff     <= 1'b0;
                            end
                        end
                    end
                end

                else
                begin
                    if(next_w_feed_in)
                    begin
                        addr_w_tmp_ff   <= user_w_addr_ff;
                        len_w_tmp_ff    <= user_w_len_ff;
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
