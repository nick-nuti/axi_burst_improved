
import fifo_pkg::*;

interface fifo_push_if #(
    parameter WIDTH
)(
    input logic clk,
    input logic rstn
);

    logic req;
    logic ack, ack_pulse;
    
    logic [WIDTH-1:0] data_in;

    logic fifo_full;
    logic stream_mode;
    
    task automatic push_fifo (
        input [WIDTH-1:0] data_in_array [],
        input int num_entries
    );
        fork
            begin : reset_detect_thread
                wait(~rstn);
                $display("TASK PUSH_FIFO: RESET ASSERTED DURING FIFO PUSH... EXITING TASK");
                disable fifo_push_thread;
            end
            
            begin : fifo_push_thread
                if(stream_mode == 0)
                begin
                    for(int i = 0; i < num_entries; i++)
                    begin
                        data_in = data_in_array[i];
                        @(posedge clk);
                        req = 1'b1;
                        wait(ack);
                        @(posedge clk);
                        req = 1'b0;
                        wait(~ack);
                    end
                end
                
                else
                begin
                    req <= 1'b1;
                
                    for(int i = 0; i < num_entries; i++)
                    begin
                        data_in <= data_in_array[i];
                        wait(ack);
                        @(posedge clk);
                    end
                    
                    req <= 1'b0;
                end
            end
        join_any
    endtask

endinterface

interface fifo_pop_if #(
    parameter WIDTH
)(
    input logic clk,
    input logic rstn
);

    logic req;
    logic ack, ack_pulse;
    
    logic [WIDTH-1:0]  data_out;

    logic fifo_empty;
    logic stream_mode;
    
    task automatic pop_fifo (
        output [WIDTH-1:0] data_out_array [$],
        input int num_entries
    );
        data_out_array.delete();
    
        fork
            begin : reset_detect_thread
                wait(~rstn);
                $display("TASK POP_FIFO: RESET ASSERTED DURING FIFO POP... EXITING TASK");
                disable fifo_pop_thread;
            end
            
            begin : fifo_pop_thread
                if(stream_mode == 0)
                begin
                    for(int i = 0; i < num_entries; i++)
                    begin
                        @(posedge clk);
                        req = 1'b1;
                        wait(ack);
                        @(posedge clk);
                        req = 1'b0;
                        data_out_array.push_back(data_out);
                        wait(~ack);
                        @(posedge clk);
                    end
                end
                
                else
                begin
                    req <= 1'b1;
                
                    for(int i = 0; i < num_entries; i++)
                    begin
                        wait(ack);
                        data_out_array.push_back(data_out);
                        @(posedge clk);
                    end
                    
                    req <= 1'b0;
                end
            end
        join_any
    endtask

endinterface
