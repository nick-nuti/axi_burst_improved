// GENERAL
localparam BYTE = 8;
localparam PAGE_SIZE_BYTES_CLOG = $clog2(PAGE_SIZE_BYTES);
localparam DATA_W_CLOG = $clog2(DATA_W);
localparam DATA_W_BYTES = DATA_W/BYTE;
localparam DATA_W_BYTES_CLOG = $clog2(DATA_W_BYTES);
localparam STRB_W_CLOG = $clog2(DATA_W_BYTES);

// AXI
localparam LEN_W            = 8;
localparam LOCK_W           = 1;
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