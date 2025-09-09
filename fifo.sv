
module fifo # (
    parameter NUM_ENTRIES=64,
    parameter DATA_W=128
) (
    input wire clk,
    input wire resetn,
    input wire wr_en,
    input wire rd_en,
    input wire [(DATA_W-1):0] din,
    output wire [(DATA_W-1):0] dout,
    output wire full,
    output wire empty
);

    reg [$clog2(NUM_ENTRIES):0] w_ptr;
    reg [$clog2(NUM_ENTRIES):0] r_ptr;
        
    wire w_cnt_inc;
    wire r_cnt_dec;

    reg [(DATA_W-1):0] ram[(NUM_ENTRIES-1):0];
    
    initial
    begin
        for(int i = 0; i < NUM_ENTRIES; i++)
        begin
            ram[i] <= 0;
        end
    end

    always@(posedge clk)
    begin
        if(~resetn)
        begin
            w_ptr   <= 0;
            r_ptr   <= 0;
        end

        else
        begin
            if(wr_en && ~full)
            begin
                ram[w_ptr] <= din;

                if(w_ptr == (NUM_ENTRIES-1))
                begin
                    w_ptr <= 0;
                end

                else
                begin
                    w_ptr <= w_ptr + 1;
                end
            end
            
            else
            begin
                w_ptr   <= w_ptr;
            end

            if(rd_en && ~empty)
            begin

                if(r_ptr == (NUM_ENTRIES-1))
                begin
                    r_ptr <= 0;
                end

                else
                begin
                    r_ptr <= r_ptr + 1;
                end
            end
            
            else
            begin
                r_ptr   <= r_ptr;
            end
        end
    end

    assign dout  = ram[r_ptr];
    assign full  = ((((NUM_ENTRIES + r_ptr)-1)%NUM_ENTRIES) == w_ptr);
    assign empty = (w_ptr == r_ptr);

endmodule
