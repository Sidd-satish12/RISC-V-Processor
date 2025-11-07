`include "sys_defs.svh"

// Branch module: compute whether to take branches (conditional and unconditional)
// This module is purely combinational
module branch (
    input DATA rs1,
    input DATA rs2,
    input BRANCH_FUNC func,  // Which branch condition to check

    output logic take  // True/False condition result
);

    always_comb begin
        case (func)
            EQ:   take = signed'(rs1) == signed'(rs2);  // BEQ
            NE:   take = signed'(rs1) != signed'(rs2);  // BNE
            LT:   take = signed'(rs1) < signed'(rs2);   // BLT
            GE:   take = signed'(rs1) >= signed'(rs2);  // BGE
            LTU:  take = rs1 < rs2;                     // BLTU
            GEU:  take = rs1 >= rs2;                    // BGEU
            JAL:  take = `TRUE;                         // JAL is always taken
            JALR: take = `TRUE;                         // JALR is always taken
            default: take = `FALSE;
        endcase
    end

endmodule  // branch
