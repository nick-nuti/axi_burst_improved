package axi_master_pkg;
    //============================
    // IP enables
    //============================
    parameter bit WRITE_EN           = 1;
    parameter bit READ_EN            = 0;

    //============================
    // AXI definitions
    //============================
    parameter int ADDR_W             = 64;
    parameter int DATA_W             = 128;
    parameter int LEN_W              = 8;
    parameter int LOCK_W             = 1;
    parameter int QOS_W              = 4;
    parameter int CACHE_W            = 4;
    parameter int ABURST_W           = 2;
    parameter int PROT_W             = 3;
    parameter int RESP_W             = 2;
    parameter int REGION_W           = 4;
    parameter int ID_W               = 4;

    //============================
    // IP specific
    //============================
    parameter int PAGE_SIZE_BYTES       = 4096;
    parameter int SPLIT_PAGE_BOUNDARY   = 0;
    parameter int BURST_POLICY          = 0;
    parameter int MISALIGN_ADJUST       = 0;
    parameter int ID_CHECK              = 0;

    //============================
    // FIFOs + Behavior
    //============================
    parameter int NUM_OUTSTANDING_WR    = 2;
    parameter int NUM_OUTSTANDING_RD    = 2;

    parameter bit CMD_PUSH_STREAM_MODE  = 0;
    parameter bit DATA_PUSH_STREAM_MODE = 0;
    parameter bit RESP_POP_STREAM_MODE  = 0;

    //============================
    // Derived localparams
    //============================
    localparam int BYTE = 8;
    localparam int PAGE_SIZE_BYTES_CLOG = $clog2(PAGE_SIZE_BYTES);
    localparam int DATA_W_CLOG = $clog2(DATA_W);
    localparam int DATA_W_BYTES = DATA_W / BYTE;
    localparam int DATA_W_BYTES_CLOG = $clog2(DATA_W_BYTES);
    localparam int STRB_W_CLOG = $clog2(DATA_W_BYTES);

    parameter int STRB_W           = DATA_W_BYTES;
    parameter int ASIZE_W          = DATA_W_BYTES_CLOG;
    parameter int MAX_BURST_BEATS  = 1 << (LEN_W);

    localparam int WR_CMD_W  = ADDR_W + LEN_W + ASIZE_W + ID_W;
    localparam int WR_DATA_W = DATA_W + STRB_W;
    localparam int WR_RESP_W = RESP_W + ID_W;
endpackage
