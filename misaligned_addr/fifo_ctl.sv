
module fifo_ctl #(
                    parameter CMD_NUM_ENTRIES,
                    parameter CMD_W,
                    parameter RESP_NUM_ENTRIES,
                    parameter RESP_W
                    )
(
        input wire clk,
        input wire resetn,
    
        output wire                             cmd_fifo_full,
        output wire                             cmd_fifo_empty,
        output wire [$clog2(CMD_NUM_ENTRIES):0] cmd_fifo_count,

        output wire                              resp_fifo_full,
        output wire                              resp_fifo_empty,
        output wire [$clog2(RESP_NUM_ENTRIES):0] resp_fifo_count,
        output wire                              resp_pop_ready,
    
    // CMD pipe
        // CPU side (CMD in)
        input  wire                              cmd_push_req, // rising pulse required; keep it high until you see ack
        input  wire [(CMD_W-1):0]                cmd_push_struct,
        output wire                              cmd_push_ack,
        output wire                              cmd_push_req_pulse,
 
        // PL side (CMD out)
        input  wire                              cmd_pop_req, // rising pulse required; keep it high until you see ack
        output wire [(CMD_W-1):0]                cmd_pop_struct,
        output wire                              cmd_pop_ack,
        output wire                              cmd_pop_req_pulse,
    
    // RESP pipe
        // PL side (RESP in)
        input  wire                              resp_push_req, // rising pulse required; keep it high until you see ack
        input  wire [(RESP_W-1):0]               resp_push_struct,
        output wire                              resp_push_ack,
        output wire                              resp_push_req_pulse,

        // CPU side (RESP out)
        input  wire                              resp_pop_req, // rising pulse required; keep it high until you see ack
        output wire [(RESP_W-1):0]               resp_pop_struct,
        output wire                              resp_pop_ack,
        output wire                              resp_pop_req_pulse
    );
    
    // CMD push
    req_pulse_ack cmd_push_req_ack (
        .clk(clk),
        .rstn(resetn),
        .req(cmd_push_req),
        .req_en(~cmd_fifo_full),
        .req_pulse_out(cmd_push_req_pulse),
        .ack(cmd_push_ack)
    );
    
    // CMD pop
    req_pulse_ack cmd_pop_req_ack (
        .clk(clk),
        .rstn(resetn),
        .req(cmd_pop_req),
        .req_en(~cmd_fifo_empty),
        .req_pulse_out(cmd_pop_req_pulse),
        .ack(cmd_pop_ack)
    );
    
    // RESP push
    req_pulse_ack resp_push_req_ack (
        .clk(clk),
        .rstn(resetn),
        .req(resp_push_req),
        .req_en(~resp_fifo_full),
        .req_pulse_out(resp_push_req_pulse),
        .ack(resp_push_ack)
    );
    
    // RESP pop
    req_pulse_ack resp_pop_req_ack (
        .clk(clk),
        .rstn(resetn),
        .req(resp_pop_req),
        .req_en(~resp_fifo_empty),
        .req_pulse_out(resp_pop_req_pulse),
        .ack(resp_pop_ack)
    );
    
    fifo # (
        .NUM_ENTRIES(CMD_NUM_ENTRIES),
        .DATA_W(CMD_W),
        .WRITE_BEFORE_READ(0)
    ) cmd_fifo (
        .clk(clk),
        .resetn(resetn),
        .wr_en(cmd_push_req_pulse),
        .rd_en(cmd_pop_req_pulse),
        .din(cmd_push_struct),
        .dout(cmd_pop_struct),
        .full(cmd_fifo_full),
        .empty(cmd_fifo_empty),
        .count(cmd_fifo_count)
    );
    
    fifo # (
        .NUM_ENTRIES(RESP_NUM_ENTRIES),
        .DATA_W(RESP_W),
        .WRITE_BEFORE_READ(0)
    ) resp_fifo (
        .clk(clk),
        .resetn(resetn),
        .wr_en(resp_push_req_pulse),
        .rd_en(resp_pop_req_pulse),
        .din(resp_push_struct),
        .dout(resp_pop_struct),
        .full(resp_fifo_full),
        .empty(resp_fifo_empty),
        .count(resp_fifo_count)
    );
    
    assign resp_pop_ready = ~resp_fifo_empty;
endmodule
