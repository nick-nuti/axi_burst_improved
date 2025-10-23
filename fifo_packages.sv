
package fifo_pkg;
    import axi_master_pkg::*;

    typedef struct packed 
    {
        logic [ADDR_W-1:0] address;
        logic [LEN_W-1:0]  awlen;
        logic [ASIZE_W-1:0]  awsize;
        logic [ID_W-1:0]  awid;
    } wr_cmd_type;

    typedef struct packed 
    {
        logic [DATA_W-1:0] wdata;
        logic [STRB_W-1:0]  wstrb;
    } wr_data_type;
    
    typedef struct packed
    {
        logic [RESP_W-1:0]     bresp;
        logic [ID_W-1:0]       bid;
    } wr_resp_type;
 endpackage

