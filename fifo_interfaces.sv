
// stream_mode:
// 0: handshake -> req -> clkcycle -> wait for ack -> lower req
// 1: valid req high -> ack high -> req can stay high to stream data through, ack is combo and will stay high as long as req is high + fifo is not full (for push) or empty (for pop)

interface fifo_push_if #(
    parameter type T = logic [63:0]
)(
    input logic clk,
    input logic rstn
);

    logic req;
    logic ack, ack_pulse;
    
    T data_in;

    logic fifo_full;
    logic stream_mode;
    
    modport master (
        output req,
        output data_in,
        input ack,
        input ack_pulse,
        input fifo_full
    );
    
    modport slave (
        input req,
        input data_in,
        output ack,
        output ack_pulse,
        output fifo_full
    );

endinterface

interface fifo_pop_if #(
    parameter type T = logic [63:0]
)(
    input logic clk,
    input logic rstn
);

    logic req;
    logic ack, ack_pulse;
    
    T data_out;

    logic fifo_empty;
    logic stream_mode;
    
    modport master (
        output req,
        input data_out,
        input ack,
        input ack_pulse,
        input fifo_empty
    );
    
    modport slave (
        input req,
        output data_out,
        output ack,
        output ack_pulse,
        output fifo_empty
    );

endinterface

task automatic push_fifo (
    fifo_push_if.master fifo_in,
    input fifo_in.T data_in_array [],
    input int num_entries
);
    fork
        begin : reset_detect_thread
            wait(~fifo_in.rstn);
            $display("TASK PUSH_FIFO: RESET ASSERTED DURING FIFO PUSH... EXITING TASK");
            disable fifo_push_thread;
        end
        
        begin : fifo_push_thread
            if(fifo_in.stream_mode == 0)
            begin
                for(int i = 0; i < num_entries; i++)
                begin
                    fifo_in.data_in <= data_in_array[i];
                    
                    fifo_in.req <= 1'b1;
                    wait(fifo_in.ack);
                    fifo_in.req <= 1'b0;
                    
                    @(posedge fifo_in.clk);
                end
            end
            
            else
            begin
                fifo_in.req <= 1'b1;
            
                for(int i = 0; i < num_entries; i++)
                begin
                    fifo_in.data_in <= data_in_array[i];
                    wait(fifo_in.ack);
                    @(posedge fifo_in.clk);
                end
                
                fifo_in.req <= 1'b0;
            end
        end
    join_any
endtask

task automatic pop_fifo (
    fifo_pop_if.master fifo_out,
    output fifo_out.T data_out_array [],
    input int num_entries
);
    fork
        begin : reset_detect_thread
            wait(~fifo_out.rstn);
            $display("TASK POP_FIFO: RESET ASSERTED DURING FIFO POP... EXITING TASK");
            disable fifo_pop_thread;
        end
        
        begin : fifo_pop_thread
            if(fifo_out.stream_mode == 0)
            begin
                for(int i = 0; i < num_entries; i++)
                begin
                    fifo_out.req <= 1'b1;
                    
                    wait(fifo_out.ack);
                    data_out_array[i] <= fifo_out.data_out;
                    
                    fifo_out.req <= 1'b0;
                    
                    @(posedge fifo_out.clk);
                end
            end
            
            else
            begin
                fifo_out.req <= 1'b1;
            
                for(int i = 0; i < num_entries; i++)
                begin
                    wait(fifo_out.ack);
                    data_out_array[i] <= fifo_out.data_out;
                    @(posedge fifo_out.clk);
                end
                
                fifo_out.req <= 1'b0;
            end
        end
    join_any
endtask