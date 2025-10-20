
// for use with CPU or interfaces that will miss clock cycles

// req = 1
// ack = 0

// req = 1
// ack = 1

// req = 0
// ack = 0

module req_ack #(
    parameter STREAM_MODE=0 // 0 = level sensitive handshake mode, >0 = streaming mode where inputs are taken when (req & req_en)
)(
    input wire clk,
    input wire rstn,
    input wire req,
    input wire req_en,
    output wire ack,
    output wire ack_pulse_out // not used in stream mode
);
    
    logic ack_r;
    
    always_ff @ (posedge clk or negedge rstn)
    begin
        if(~rstn)
        begin
            ack_r <= 0;         
        end

        else
        begin
            if(~STREAM_MODE)
            begin
                if (req & req_en & ~ack_r) ack_r <= 1'b1;

                else if (~req) ack_r <= 1'b0;
            end
        end
    end

    assign ack = (STREAM_MODE) ? (req & req_en) : ack_r;

    assign ack_pulse_out = (STREAM_MODE) ? (req & req_en) : (req & req_en & ~ack_r);

endmodule
