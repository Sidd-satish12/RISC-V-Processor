// -----------------------------------------------------------------------------
// Store Queue FIFO (simple, registered I/O)
// - Depth comes from `LSQ_SZ` (set in sys_defs.svh)
// - Payload type: store_queue_entry_t (defined in sys_defs.svh)
// - Enqueue from DISPATCH/ISSUE; Dequeue at RETIRE
// - All acks and outputs are registered (no combinational assigns)
// - Allows same-cycle enqueue+dequeue
// -----------------------------------------------------------------------------
`include "sys_defs.svh"

module store_queue_fifo (
  input  logic  clock,
  input  logic  reset,

  // ---------------- Enqueue side (from store creation) -----------------------
  input  logic                        enqueue_request_i,
  input  logic [$bits(ADDR)-1:0]      enqueue_store_address_i,
  input  logic [$bits(DATA)-1:0]      enqueue_store_data_i,
  input  logic [($bits(DATA)/8)-1:0]  enqueue_store_byte_enable_i,
  output logic                        enqueue_accepted_o,    // 1-cycle pulse

  // ---------------- Dequeue side (to retirement/commit) ----------------------
  input  logic                        dequeue_request_i,
  output logic [$bits(ADDR)-1:0]      dequeue_store_address_o,
  output logic [$bits(DATA)-1:0]      dequeue_store_data_o,
  output logic [($bits(DATA)/8)-1:0]  dequeue_store_byte_enable_o,
  output logic                        dequeue_accepted_o     // 1-cycle pulse
);

  // ====== Config from sys_defs ======
  localparam int unsigned STORE_QUEUE_DEPTH = `LSQ_SZ;
  localparam int unsigned PTR_WIDTH =
      (STORE_QUEUE_DEPTH <= 1) ? 1 : $clog2(STORE_QUEUE_DEPTH);

  // ====== Storage and state ======
  store_queue_entry_t             circular_buffer [STORE_QUEUE_DEPTH];
  logic [PTR_WIDTH-1:0]           head_index_q;   // oldest valid entry
  logic [PTR_WIDTH-1:0]           tail_index_q;   // next free slot
  logic [PTR_WIDTH:0]             entry_count_q;  // 0..STORE_QUEUE_DEPTH

  // Wrap-safe pointer increment
  function automatic logic [PTR_WIDTH-1:0]
    next_index(input logic [PTR_WIDTH-1:0] idx);
    if (idx == STORE_QUEUE_DEPTH - 1)
      next_index = '0;
    else
      next_index = idx + 1'b1;
  endfunction

  // ====== Sequential logic only ======
  always_ff @(posedge clock) begin
    if (reset) begin
      head_index_q                 <= '0;
      tail_index_q                 <= '0;
      entry_count_q                <= '0;

      enqueue_accepted_o           <= 1'b0;
      dequeue_accepted_o           <= 1'b0;

      dequeue_store_address_o      <= '0;
      dequeue_store_data_o         <= '0;
      dequeue_store_byte_enable_o  <= '0;

    end else begin
      // default: deassert 1-cycle pulses
      enqueue_accepted_o <= 1'b0;
      dequeue_accepted_o <= 1'b0;

      // availability
      logic queue_is_not_empty = (entry_count_q != 0);
      logic queue_is_not_full  = (entry_count_q != STORE_QUEUE_DEPTH);

      // decide operations (allow enqueue if a same-cycle dequeue makes room)
      logic will_dequeue = (dequeue_request_i && queue_is_not_empty);
      logic will_enqueue = (enqueue_request_i &&
                            (queue_is_not_full || (dequeue_request_i && queue_is_not_empty)));

      // -------- Dequeue first: present head to outputs, advance head --------
      if (will_dequeue) begin
        dequeue_store_address_o      <= circular_buffer[head_index_q].store_address;
        dequeue_store_data_o         <= circular_buffer[head_index_q].store_data;
        dequeue_store_byte_enable_o  <= circular_buffer[head_index_q].store_byte_enable;
        head_index_q                 <= next_index(head_index_q);
        dequeue_accepted_o           <= 1'b1;
      end

      // -------- Enqueue: write at tail, advance tail ------------------------
      if (will_enqueue) begin
        circular_buffer[tail_index_q] <= '{
          store_address     : enqueue_store_address_i,
          store_data        : enqueue_store_data_i,
          store_byte_enable : enqueue_store_byte_enable_i
        };
        tail_index_q        <= next_index(tail_index_q);
        enqueue_accepted_o  <= 1'b1;
      end

      // -------- Maintain occupancy counter ---------------------------------
      unique case ({will_enqueue, will_dequeue})
        2'b10: entry_count_q <= entry_count_q + 1'b1; // enqueue only
        2'b01: entry_count_q <= entry_count_q - 1'b1; // dequeue only
        default: /* both or neither => no net change */ ;
      endcase
    end
  end

endmodule
