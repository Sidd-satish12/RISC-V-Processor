module LFSR #(
    parameter WIDTH = 6,
    parameter INIT_VALUE = 682  // 1010101010 (alternating 1s and 0s pattern)
)(
    input clk,
    input rst,
    output reg [WIDTH-1:0] op
);
    always@(posedge clk) begin
        if(rst) begin
            op <= INIT_VALUE[WIDTH-1:0];
        end else begin
            // Standard LFSR: shift left, XOR bits WIDTH-1 and WIDTH-2 for feedback
            op <= {op[WIDTH-2:0], (op[WIDTH-1] ^ op[WIDTH-2])};
        end
    end
endmodule

