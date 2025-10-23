`timescale 1ns / 1ps

import axi_master_pkg::*;
import fifo_pkg::*;

import axi_vip_pkg::*;
import design_1_axi_vip_0_0_pkg::*;

module testbench_top();
    reg                           test_start_ready;
    reg                           aclk;
    reg                           aresetn;
    
    xil_axi_uint slv_mem_agent_verbosity = 400;
    design_1_axi_vip_0_0_slv_mem_t slv_mem_agent;
    reg axi_ready;

    initial
    begin
        axi_ready = 0;
        slv_mem_agent = new("slave vip agent",d1w0.design_1_i.axi_vip_0.inst.IF);
        slv_mem_agent.set_agent_tag("Slave VIP");
        slv_mem_agent.set_verbosity(slv_mem_agent_verbosity);
        slv_mem_agent.start_slave();
    
        axi_ready = 1;
    end

/*
// IP enables
    parameter WRITE_EN           = 1;
    parameter READ_EN            = 0;
// AXI definitions
    parameter ADDR_W             = 64;
    parameter DATA_W             = 128;
    parameter LEN_W              = 8;
    parameter LOCK_W             = 1;
    parameter QOS_W              = 4;
    parameter CACHE_W            = 4;
    parameter ABURST_W           = 2;
    parameter PROT_W             = 3;
    parameter RESP_W             = 2;
    parameter REGION_W           = 4;
    parameter ID_W               = 4;
// IP specific definitions
    parameter PAGE_SIZE_BYTES       = 4096;
    parameter SPLIT_PAGE_BOUNDARY   = 0; // 0: end burst at page boundary, >0: split burst at page boundary
    parameter BURST_POLICY          = 0; // 0: (safe) require full burst upfront, 1: stream, wait until data is present by lowering wvalid, 2: pad with dummy data if fifo empty
    parameter MISALIGN_ADJUST       = 0; // 0: disallow (results in error), >0: allow
    parameter ID_CHECK              = 0; // 0: disallow, >0: allow
// FIFOs
    parameter NUM_OUTSTANDING_WR    = 2;
    parameter NUM_OUTSTANDING_RD    = 2;

    parameter CMD_PUSH_STREAM_MODE  = 0; // 0 = level sensitive handshake mode, >0 = streaming mode where inputs are taken when (req & req_en)
    parameter DATA_PUSH_STREAM_MODE = 0; // 0 = level sensitive handshake mode, >0 = streaming mode where inputs are taken when (req & req_en)
    parameter RESP_POP_STREAM_MODE  = 0; // 0 = level sensitive handshake mode, >0 = streaming mode where inputs are taken when (req & req_en)
    
    localparam BYTE = 8;
    localparam PAGE_SIZE_BYTES_CLOG = $clog2(PAGE_SIZE_BYTES);
    localparam DATA_W_CLOG = $clog2(DATA_W);
    localparam DATA_W_BYTES = DATA_W/BYTE;
    localparam DATA_W_BYTES_CLOG = $clog2(DATA_W_BYTES);
    localparam STRB_W_CLOG = $clog2(DATA_W_BYTES);
    
    parameter STRB_W           = DATA_W_BYTES;
    parameter ASIZE_W          = DATA_W_BYTES_CLOG;
    parameter MAX_BURST_BEATS  = 1 << (LEN_W);
    
    // WRITE FIFO LOCALPARAMs
    localparam WR_CMD_W = ADDR_W + LEN_W + ASIZE_W + ID_W;
    localparam WR_DATA_W = DATA_W + STRB_W;
    localparam WR_RESP_W = RESP_W + ID_W;
*/
/**************** Write Address Channel Signals ****************/
    wire [ADDR_W-1:0]             m_axi_awaddr;    // address
    wire [PROT_W-1:0]             m_axi_awprot;    // protection - privilege and securit level of transaction
    wire                          m_axi_awvalid;   //
    wire                          m_axi_awready;   //
    wire [ASIZE_W-1:0]            m_axi_awsize;    //3'b100, // burst size - size of each transfer in the burst 3'b100 for 16 bytes/ 128 bit
    wire [ABURST_W-1:0]           m_axi_awburst;   // fixed burst = 00, incremental = 01, wrapped burst = 10
    wire [CACHE_W-1:0]            m_axi_awcache;   // cache type - how transaction interacts with caches
    wire [LEN_W-1:0]              m_axi_awlen;    // number of data transfers in the burst (0-255) (done)
    wire [LOCK_W-1:0]             m_axi_awlock;    // lock type - indicates if transaction is part of locked sequence
    wire [QOS_W-1:0]              m_axi_awqos;     // quality of service - transaction indication of priority level
    wire [REGION_W-1:0]           m_axi_awregion;  // region identifier - identifies targetted region
    wire [ID_W-1:0]               m_axi_awid;
/**************** Write Data Channel Signals ****************/
    wire [DATA_W-1:0]             m_axi_wdata;     //
    wire [STRB_W-1:0]             m_axi_wstrb;     //
    wire                          m_axi_wvalid;    // set to 1 when data is ready to be transferred (done)
    wire                          m_axi_wready;    // 
    wire                          m_axi_wlast;     // if awlen=0 then set wlast (done)
/**************** Write Response Channel Signals ****************/
    wire [RESP_W-1:0]             m_axi_bresp;     // write response - status of the write transaction (00 = okay, 01 = exokay, 10 = slverr, 11 = decerr)
    wire                          m_axi_bvalid;    // write response valid - 0 = response not valid, 1 = response is valid
    wire                          m_axi_bready;    // write response ready - 0 = not ready, 1 = ready
    wire [ID_W-1:0]               m_axi_bid;
/**************** Read Address Channel Signals ****************/
    wire [ADDR_W-1:0]             m_axi_araddr;    // read address
    wire [PROT_W-1:0]             m_axi_arprot;    // protection - privilege and securit level of transaction
    wire                          m_axi_arvalid;   // 
    wire                          m_axi_arready;   // 
    wire [ASIZE_W-1:0]            m_axi_arsize;    //3'b100, // burst beat size - size of each transfer in the burst 3'b100 for 16 bytes/ 128 bit
    wire [ABURST_W-1:0]           m_axi_arburst;   // fixed burst = 00, incremental = 01, wrapped burst = 10
    wire [CACHE_W-1:0]            m_axi_arcache;   // cache type - how transaction interacts with caches
    wire [LEN_W-1:0]              m_axi_arlen;     // number of data transfers in the burst (0-255) (done)
    wire [LOCK_W-1:0]             m_axi_arlock;    // lock type - indicates if transaction is part of locked sequence
    wire [QOS_W-1:0]              m_axi_arqos;     // quality of service - transaction indication of priority level
    wire [REGION_W-1:0]           m_axi_arregion;  // region identifier - identifies targetted region
    wire [ID_W-1:0]               m_axi_arid;
/**************** Read Data Channel Signals ****************/
    wire                          m_axi_rready;    // read ready - 0 = not ready, 1 = ready
    wire [DATA_W-1:0]             m_axi_rdata;     // 
    wire                          m_axi_rvalid;    // read response valid - 0 = response not valid, 1 = response is valid
    wire                          m_axi_rlast;     // =1 when on last read
    wire [ID_W-1:0]               m_axi_rid;
/**************** Read Response Channel Signals ****************/
    wire [RESP_W-1:0]             m_axi_rresp;     // read response - status of the read transaction (00 = okay, 01 = exokay, 10 = slverr, 11 = decerr)
/**************** User Control Signals ****************/
    
    wr_cmd_type write_cmd; 
    logic [WR_CMD_W-1:0] write_cmd_concat [$]; // queue
    wr_data_type write_data;
    logic [WR_DATA_W-1:0] write_data_concat [$]; // queue
    wr_resp_type write_resp, write_resp_print;
    logic [WR_RESP_W-1:0] write_resp_concat [$];
    
    fifo_push_if #(.WIDTH(WR_CMD_W))   write_fifo_cmd_in_intf (.clk(aclk), .rstn(aresetn));
    fifo_push_if #(.WIDTH(WR_DATA_W))  write_fifo_data_in_intf (.clk(aclk), .rstn(aresetn));
    fifo_pop_if  #(.WIDTH(WR_RESP_W))  write_fifo_resp_out_intf (.clk(aclk), .rstn(aresetn));
    
    task automatic fill_axi_commands();
        wr_cmd_type write_cmd_temp;
        wr_data_type write_data_temp;
        
        logic [WR_CMD_W-1:0] write_cmd_concat_bits;
        logic [WR_DATA_W-1:0] write_data_concat_bits;
        
        write_cmd_temp.address = 'h1000000000000;
        write_cmd_temp.awlen = 255;
        write_cmd_temp.awsize = $clog2(DATA_W/8);
        write_cmd_temp.awid = 1;
        
        write_cmd_concat.push_back(write_cmd_temp);
                                            
        foreach(write_cmd_concat[i])
        begin
            for(int j = 0; j <= write_cmd_concat[i][WR_CMD_W-ADDR_W -: LEN_W]; j++)
            begin
                write_data_temp.wdata = 'hF000000000000000 + j;
                write_data_temp.wstrb = {STRB_W{1'b1}};
                
                write_data_concat.push_back(write_data_temp);
            end
        end
    endtask
    
    task automatic test_start();
        
        int index = 0;
    
        write_fifo_cmd_in_intf.push_fifo(write_cmd_concat, 1);
        write_fifo_data_in_intf.push_fifo(write_data_concat, write_cmd_concat[index][WR_CMD_W-ADDR_W -: LEN_W]);
    endtask
    
    initial
    begin
        test_start_ready = 0;
        aclk = 0;
        aresetn = 0;
    
        wait(axi_ready);
        
        // WRITE FIFO INTERFACE - STREAM MODE SETTING
        write_fifo_cmd_in_intf.stream_mode      = CMD_PUSH_STREAM_MODE;
        write_fifo_data_in_intf.stream_mode     = DATA_PUSH_STREAM_MODE;
        write_fifo_resp_out_intf.stream_mode    = RESP_POP_STREAM_MODE;
        
        // WRITE FIFO INTERFACE - ZERO OUT 
        write_fifo_cmd_in_intf.req = 'h0;
        write_fifo_cmd_in_intf.data_in = 'h0;
    
        write_fifo_data_in_intf.req = 'h0;
        write_fifo_data_in_intf.data_in = 'h0;

        write_fifo_resp_out_intf.req = 'h0;
        write_fifo_resp_out_intf.data_out = 'h0;
        
        #5us;
        aresetn = 1;
        #10us;
        
        fill_axi_commands();        
        test_start();
        
        write_fifo_resp_out_intf.pop_fifo(write_resp_concat, 1);
        write_resp_print = write_resp_concat[0];
        
        $display("RECEIVED WRITE RESPONSE: BRESP = 0x%X BID = 0x%X", write_resp_print.bresp, write_resp_print.bid);
        
       #100us;
       
       $finish;
    end
    
    always
    begin
        #10ns aclk = ~aclk;
    end
    
    /*EXAMPLE
    initial begin
        push_fifo(wr_cmd_push_if.master, my_cmd_array, num_entries);
        push_fifo(wr_data_push_if.master, my_data_array, num_entries);
        pop_fifo(wr_resp_pop_if.master, my_resp_array, num_entries);
    end
    */
    
    assign write_cmd = write_fifo_cmd_in_intf.data_in;
    assign write_data = write_fifo_data_in_intf.data_in;
    assign write_fifo_resp_out_intf.data_out = write_resp;

    abm_w_fifo #(
    // IP enables
        .WRITE_EN(WRITE_EN), .READ_EN(READ_EN),
        
    // AXI definitions
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(LEN_W), .LOCK_W(LOCK_W), .QOS_W(QOS_W), .CACHE_W(CACHE_W), 
        .ABURST_W(ABURST_W), .PROT_W(PROT_W), .RESP_W(RESP_W), .REGION_W(REGION_W), .ID_W(ID_W),
        
    // IP specific definitions
        .PAGE_SIZE_BYTES(PAGE_SIZE_BYTES),
        .SPLIT_PAGE_BOUNDARY(SPLIT_PAGE_BOUNDARY),  // 0: end burst at page boundary
                                                    // >0: split burst at page boundary
                                    
        .BURST_POLICY(BURST_POLICY),    // 0: (safe) require full burst upfront
                                        // 1: stream, wait until data is present by lowering wvalid
                                        // 2: pad with dummy data if fifo empty
                                    
        .MISALIGN_ADJUST(MISALIGN_ADJUST),  // 0: disallow (results in error)
                                            // >0: allow
                                    
        .ID_CHECK(ID_CHECK),    // 0: disallow
                                // >0: allow
    // FIFOs
        .NUM_OUTSTANDING_WR(NUM_OUTSTANDING_WR), // only works if "ID_CHECK is allowed"
        .NUM_OUTSTANDING_RD(NUM_OUTSTANDING_RD), // only works if "ID_CHECK is allowed"
    
        .CMD_PUSH_STREAM_MODE(CMD_PUSH_STREAM_MODE),   // 0 = level sensitive handshake mode, >0 = streaming mode where inputs are taken when (req & req_en)
        .DATA_PUSH_STREAM_MODE(DATA_PUSH_STREAM_MODE), // 0 = level sensitive handshake mode, >0 = streaming mode where inputs are taken when (req & req_en)
        .RESP_POP_STREAM_MODE(RESP_POP_STREAM_MODE)    // 0 = level sensitive handshake mode, >0 = streaming mode where inputs are taken when (req & req_en)
    ) awf0 (
    // AXI
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
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_bid(m_axi_bid),
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
        .m_axi_rready(m_axi_rready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rid(m_axi_rid),
        .m_axi_rresp(m_axi_rresp),
    
        .aclk(aclk),
        .aresetn(aresetn),
    
        .wr_cmd_push_req(write_fifo_cmd_in_intf.req),
        .wr_cmd_push_struct_address(write_cmd.address),
        .wr_cmd_push_struct_awlen(write_cmd.awlen),
        .wr_cmd_push_struct_awsize(write_cmd.awsize),
        .wr_cmd_push_struct_awid(write_cmd.awid),
        .wr_cmd_push_ack(write_fifo_cmd_in_intf.ack),
    
        .wr_cmd_fifo_full(write_fifo_cmd_in_intf.fifo_full),
        .wr_cmd_fifo_empty(),
        .wr_cmd_fifo_count(),
    
        .wr_data_push_req(write_fifo_data_in_intf.req),
        .wr_data_push_struct_wdata(write_data.wdata),
        .wr_data_push_struct_wstrb(write_data.wstrb),
        .wr_data_push_ack(write_fifo_data_in_intf.ack),
    
        .wr_data_fifo_full(write_fifo_data_in_intf.fifo_full),
        .wr_data_fifo_empty(),
        .wr_data_fifo_count(),
       
        .wr_resp_pop_req(write_fifo_resp_out_intf.req),
        .wr_resp_pop_struct_bresp(write_resp.bresp),
        .wr_resp_pop_struct_bid(write_resp.bid),
        .wr_resp_pop_ack(write_fifo_resp_out_intf.ack),
    
        .wr_resp_fifo_full(),
        .wr_resp_fifo_empty(write_fifo_resp_out_intf.fifo_empty),
        .wr_resp_fifo_count()
    );
    
    // AXI SLAVE SIMULATION VIP
    design_1_wrapper d1w0 (
      .aclk_0(aclk),
      .aresetn_0(aresetn),
      .S_AXI_0_awaddr(m_axi_awaddr),
      .S_AXI_0_awlen(m_axi_awlen),
      .S_AXI_0_awsize(m_axi_awsize),
      .S_AXI_0_awburst(m_axi_awburst),
      .S_AXI_0_awlock(m_axi_awlock),
      .S_AXI_0_awcache(m_axi_awcache),
      .S_AXI_0_awid(m_axi_awid),
      .S_AXI_0_awprot(m_axi_awprot),
      .S_AXI_0_awregion(m_axi_awregion),
      .S_AXI_0_awqos(m_axi_awqos),
      .S_AXI_0_awvalid(m_axi_awvalid),
      .S_AXI_0_bid(m_axi_bid),
      .S_AXI_0_awready(m_axi_awready),
      .S_AXI_0_wdata(m_axi_wdata),
      .S_AXI_0_wstrb(m_axi_wstrb),
      .S_AXI_0_wlast(m_axi_wlast),
      .S_AXI_0_wvalid(m_axi_wvalid),
      .S_AXI_0_wready(m_axi_wready),
      .S_AXI_0_bresp(m_axi_bresp),
      .S_AXI_0_bvalid(m_axi_bvalid),
      .S_AXI_0_bready(m_axi_bready),
      .S_AXI_0_araddr(m_axi_araddr),
      .S_AXI_0_arlen(m_axi_arlen),
      .S_AXI_0_arsize(m_axi_arsize),
      .S_AXI_0_arburst(m_axi_arburst),
      .S_AXI_0_arlock(m_axi_arlock),
      .S_AXI_0_arcache(m_axi_arcache),
      .S_AXI_0_arid(m_axi_arid),
      .S_AXI_0_arprot(m_axi_arprot),
      .S_AXI_0_arregion(m_axi_arregion),
      .S_AXI_0_arqos(m_axi_arqos),
      .S_AXI_0_arvalid(m_axi_arvalid),
      .S_AXI_0_arready(m_axi_arready),
      .S_AXI_0_rdata(m_axi_rdata),
      .S_AXI_0_rresp(m_axi_rresp),
      .S_AXI_0_rlast(m_axi_rlast),
      .S_AXI_0_rid(m_axi_rid),
      .S_AXI_0_rvalid(m_axi_rvalid),
      .S_AXI_0_rready(m_axi_rready)
    );

endmodule

// NEED TO DO:
// ID_CHECK + NUM_OUTSTANDING is not implemented fully

// 1. add assertions

/* 2.
simulation automation:
(TCL)
foreach bp {0 1 2} {
  foreach sm {0 1} {
    set_property generic "BURST_POLICY=$bp STREAM_MODE=$sm" [current_fileset]
    launch_simulation -runall
  }
}
*/

/* 3. coverage
covergroup cg_axi_burst @(posedge clk);
  coverpoint BURST_POLICY { bins policy[] = {0,1,2}; }
  coverpoint STREAM_MODE  { bins sm[] = {0,1}; }
  coverpoint m_axi_awlen  { bins burstlen[] = {[0:255]}; }
  coverpoint m_axi_awaddr[11:0] { bins align[] = {0, 4, 8, 12, 0xFF0}; }
  cross BURST_POLICY, STREAM_MODE;
endgroup
*/
