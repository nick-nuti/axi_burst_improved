
module wr_fifo_group #(
                    parameter CMD_NUM_ENTRIES,
                    parameter CMD_W,
                    parameter CMD_PUSH_STREAM_MODE,
                    parameter CMD_POP_STREAM_MODE,

                    parameter DATA_NUM_ENTRIES,
                    parameter DATA_W,
                    parameter DATA_PUSH_STREAM_MODE,
                    parameter DATA_POP_STREAM_MODE,

                    parameter RESP_NUM_ENTRIES,
                    parameter RESP_W,
                    parameter RESP_PUSH_STREAM_MODE,
                    parameter RESP_POP_STREAM_MODE
                    )
(
        input wire clk,
        input wire resetn,

    // CMD pipe
        // CMD -> FIFO (push command)
        input wire              cmd_push_req, // rising pulse required; keep it high until you see ack
        input [(CMD_W-1):0]     cmd_push_struct,
        output wire             cmd_push_ack,
        output wire             cmd_push_ack_pulse,
 
        // FIFO -> ... (pop command)
        input wire              cmd_pop_req, // rising pulse required; keep it high until you see ack
        output [(CMD_W-1):0]    cmd_pop_struct,
        output wire             cmd_pop_ack,
        output wire             cmd_pop_ack_pulse,

        // FIFO INFO
        output wire cmd_fifo_full,
        output wire cmd_fifo_empty,
        output [$clog2(CMD_NUM_ENTRIES):0] cmd_fifo_count,

    // DATA IN PIPE
        // DATA -> FIFO (push data)
        input wire              data_push_req, // rising pulse required; keep it high until you see ack
        input [(DATA_W-1):0]    data_push_struct,
        output wire             data_push_ack,
        output wire             data_push_ack_pulse,

        // FIFO -> ... (pop data)
        input wire              data_pop_req, // rising pulse required; keep it high until you see ack
        output [(DATA_W-1):0]   data_pop_struct,
        output wire             data_pop_ack,
        output wire             data_pop_ack_pulse,

        // FIFO INFO
        output wire data_fifo_full,
        output wire data_fifo_empty,
        output [$clog2(DATA_NUM_ENTRIES):0] data_fifo_count,
    
    // RESP pipe
        // FIFO <- RESP (push resp)
        input wire              resp_push_req, // rising pulse required; keep it high until you see ack
        input [(RESP_W-1):0]    resp_push_struct,
        output wire             resp_push_ack,
        output wire             resp_push_ack_pulse,

        // ... <- FIFO (pop resp)
        input wire              resp_pop_req, // rising pulse required; keep it high until you see ack
        output [(RESP_W-1):0]   resp_pop_struct,
        output wire             resp_pop_ack,
        output wire             resp_pop_ack_pulse,

        // FIFO INFO
        output wire resp_fifo_full,
        output wire resp_fifo_empty,
        output [$clog2(RESP_NUM_ENTRIES):0] resp_fifo_count
    );

    fifo_improved #(
        .NUM_ENTRIES(CMD_NUM_ENTRIES),
        .DATA_WIDTH(CMD_W),
        .PUSH_STREAM_MODE(CMD_PUSH_STREAM_MODE),
        .POP_STREAM_MODE(CMD_POP_STREAM_MODE)
    ) wr_cmd_fifo0 (
        .clk(clk),
        .resetn(resetn),

        .fifo_full(cmd_fifo_full),
        .fifo_empty(cmd_fifo_empty),
        .fifo_count(cmd_fifo_count),

        .push_req(cmd_push_req),
        .push_struct(cmd_push_struct),
        .push_ack(cmd_push_ack),
        .push_ack_pulse(cmd_push_ack_pulse),

        .pop_req(cmd_pop_req),
        .pop_struct(cmd_pop_struct),
        .pop_ack(cmd_pop_ack),
        .pop_ack_pulse(cmd_pop_ack_pulse)
    );

    fifo_improved #(
        .NUM_ENTRIES(DATA_NUM_ENTRIES),
        .DATA_WIDTH(DATA_W),
        .PUSH_STREAM_MODE(DATA_PUSH_STREAM_MODE),
        .POP_STREAM_MODE(DATA_POP_STREAM_MODE)
    ) wr_data_fifo0 (
        .clk(clk),
        .resetn(resetn),

        .fifo_full(data_fifo_full),
        .fifo_empty(data_fifo_empty),
        .fifo_count(data_fifo_count),

        .push_req(data_push_req),
        .push_struct(data_push_struct),
        .push_ack(data_push_ack),
        .push_ack_pulse(data_push_ack_pulse),

        .pop_req(data_pop_req),
        .pop_struct(data_pop_struct),
        .pop_ack(data_pop_ack),
        .pop_ack_pulse(data_pop_ack_pulse)
    );

    fifo_improved #(
        .NUM_ENTRIES(RESP_NUM_ENTRIES),
        .DATA_WIDTH(RESP_W),
        .PUSH_STREAM_MODE(RESP_PUSH_STREAM_MODE),
        .POP_STREAM_MODE(RESP_POP_STREAM_MODE)
    ) wr_resp_fifo0 (
        .clk(clk),
        .resetn(resetn),

        .fifo_full(resp_fifo_full),
        .fifo_empty(resp_fifo_empty),
        .fifo_count(resp_fifo_count),

        .push_req(resp_push_req),
        .push_struct(resp_push_struct),
        .push_ack(resp_push_ack),
        .push_ack_pulse(resp_push_ack_pulse),

        .pop_req(resp_pop_req),
        .pop_struct(resp_pop_struct),
        .pop_ack(resp_pop_ack),
        .pop_ack_pulse(resp_pop_ack_pulse)
    );

endmodule
