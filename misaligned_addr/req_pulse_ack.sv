
// for use with CPU or interfaces that will miss clock cycles

// req = 1
// ack = 0

// req = 1
// ack = 1

// req = 0
// ack = 0

module req_pulse_ack (
    input wire clk,
    input wire rstn,
    input wire req,
    input wire req_en,
    output wire req_pulse_out,
    output reg ack
);
    
    logic [1:0] req_dff;
    wire        req_posedge;
    wire        req_negedge;
    
    always_ff @ (posedge clk or negedge rstn)
    begin
        if(~rstn)
        begin
            req_dff <= 2'b00;         
            ack <= 0;   
        end

        else
        begin
            if(req_en) req_dff[0] <= req;
            else req_dff[0] <= 0;
            
            if(req_posedge) ack <= 1;
            else if(req_negedge) ack <= 0;
            else ack <= ack;
        end
    end
    
    assign req_posedge = (req & ~req_dff[0] & req_en);
    assign req_negedge = (~req & (ack || req_dff[0]));
    
    assign req_pulse_out = req_posedge & ~ack;
endmodule
