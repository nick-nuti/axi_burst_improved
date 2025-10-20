
module fifo_improved #(
                    parameter NUM_ENTRIES,
                    parameter DATA_WIDTH,
                    parameter PUSH_STREAM_MODE,
                    parameter POP_STREAM_MODE
                )
(
        input wire clk,
        input wire resetn,
    
        output wire fifo_full,
        output wire fifo_empty,
        output [$clog2(NUM_ENTRIES):0] fifo_count,
    
    // (DATA in)
        input wire                      push_req,
        input [(DATA_WIDTH-1):0]        push_struct,
        output wire                     push_ack,
        output wire                     push_ack_pulse,
 
    // (DATA out)
        input wire                      pop_req,
        output [(DATA_WIDTH-1):0]       pop_struct,
        output wire                     pop_ack,
        output wire                     pop_ack_pulse
    );
    
// data push
    req_ack #(
        .STREAM_MODE(PUSH_STREAM_MODE)
    ) 
    req_ack_data_push0 (
        .clk(clk),
        .rstn(resetn),
        .req(push_req),
        .req_en(~fifo_full),
        .ack(push_ack),
        .ack_pulse_out(push_ack_pulse)
    );
    
// data pop
    req_ack #(
        .STREAM_MODE(POP_STREAM_MODE)
    ) req_ack_data_pop0 (
        .clk(clk),
        .rstn(resetn),
        .req(pop_req),
        .req_en(~fifo_empty),
        .ack(pop_ack),
        .ack_pulse_out(pop_ack_pulse)
    );

// data fifo
    fifo # (
        .NUM_ENTRIES(NUM_ENTRIES),
        .DATA_W(DATA_WIDTH)
    ) data_fifo0 (
        .clk(clk),
        .resetn(resetn),
        .wr_en(push_ack_pulse),
        .rd_en(pop_ack_pulse),
        .din(push_struct),
        .dout(pop_struct),
        .full(fifo_full),
        .empty(fifo_empty),
        .count(fifo_count)
    );

endmodule
