`include "sys_defs.svh"

module reg_file #(
    parameter int NUM_READ_PORTS  = `NUM_FU_TOTAL,
    parameter int NUM_WRITE_PORTS = `CDB_SZ
) (
    input logic clock,
    input logic reset,

    input PHYS_TAG [NUM_READ_PORTS-1:0] read_tags,
    output DATA    [NUM_READ_PORTS-1:0] read_outputs,

    input logic    [NUM_WRITE_PORTS-1:0] write_en,    // At most `N inst completes
    input PHYS_TAG [NUM_WRITE_PORTS-1:0] write_tags,
    input DATA     [NUM_WRITE_PORTS-1:0] write_data
);

    DATA [`PHYS_REG_SZ_R10K-1:0]
        register_file_entries,
        register_file_entries_next;  // synthesis inference: packed array -> flip flops,  unpacked array -> RAM

    always_comb begin
        register_file_entries_next = register_file_entries;

        for (int i = 0; i < NUM_READ_PORTS; i++) begin
            if (read_tags[i] == '0) begin  // 0 register read
                read_outputs[i] = '0;
            end else begin
                // Check for write forwarding from any write port
                logic forwarded = 1'b0;
                DATA  forwarded_data = '0;
                for (int j = 0; j < NUM_WRITE_PORTS; j++) begin
                    if (write_en[j] && read_tags[i] == write_tags[j]) begin
                        forwarded = 1'b1;
                        forwarded_data = write_data[j];
                    end
                end

                if (forwarded) begin
                    read_outputs[i] = forwarded_data;
                end else begin
                    read_outputs[i] = register_file_entries[read_tags[i]];  // normal read
                end
            end
        end

        for (int i = 0; i < NUM_WRITE_PORTS; i++) begin
            if (write_en[i]) begin
                register_file_entries_next[write_tags[i]] = write_data[i];
            end
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            register_file_entries <= '0;
        end else begin
            register_file_entries <= register_file_entries_next;
        end
    end

endmodule
