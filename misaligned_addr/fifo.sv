
module fifo # (
    parameter NUM_ENTRIES=64,
    parameter DATA_W=128,
    parameter WRITE_BEFORE_READ=0 // 0 = READ BEFORE WRITE, >0 = WRITE BEFORE READ
) (
    input wire clk,
    input wire resetn,
    input wire wr_en,
    input wire rd_en,
    input wire [(DATA_W-1):0] din,
    output wire [(DATA_W-1):0] dout,
    output wire full,
    output wire empty,
    output reg [$clog2(NUM_ENTRIES):0] count // can't be minus 1 because 0 is not a valid entry; therefore counter goes from 1 to NUM_ENTRIES
);

    reg [$clog2(NUM_ENTRIES):0] w_ptr;
    reg [$clog2(NUM_ENTRIES):0] r_ptr;

    reg [(DATA_W-1):0] ram[(NUM_ENTRIES-1):0];

    reg [(DATA_W-1):0] w_b_r_data_ff;
    
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
            w_ptr           <= 0;
            r_ptr           <= 0;
            w_b_r_data_ff   <= 'h0;
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
                
                if(WRITE_BEFORE_READ)
                begin
                    if(wr_en && (w_ptr == r_ptr))
                    begin
                        w_b_r_data_ff <= din;
                    end

                    else
                    begin
                        w_b_r_data_ff <= ram[r_ptr];
                    end
                end
            end
            
            else
            begin
                r_ptr   <= r_ptr;
            end
        end
    end

    always@(posedge clk)
    begin
        if(~resetn)
        begin
            count <= 'h0;
        end

        else
        begin
            case({wr_en && ~full, rd_en && ~empty})
                2'b10:      count <= count+1;
                2'b01:      count <= count-1;
                2'b11:      count <= count;
                default:    count <= count;
            endcase
        end
    end

    assign dout  = (WRITE_BEFORE_READ) ? w_b_r_data_ff: ram[r_ptr];
    assign full  = (count == NUM_ENTRIES);
    assign empty = (count == 0);

endmodule
