module LFSR(input clk, rst, output reg [4:0] op);
  always@(posedge clk) begin
    if(rst) op <= 6'h3;
    else op = {op[3:0],(op[4]^op[3])};
  end
endmodule

