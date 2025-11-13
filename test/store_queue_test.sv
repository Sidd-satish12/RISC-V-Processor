`timescale 1ns/1ps
`default_nettype none

`include "sys_defs.svh"

module tb_store_queue_fifo;

  // ---------- Clock/Reset ----------
  logic clock = 0;
  logic reset = 1;
  localparam int CLK_HALF = 5; // 100 MHz
  always #(CLK_HALF) clock = ~clock;

  task automatic apply_reset();
    reset = 1;
    repeat (3) @(posedge clock);
    reset = 0;
    @(posedge clock);
  endtask

  // ---------- DUT I/O ----------
  logic                        enqueue_request_i;
  logic [$bits(ADDR)-1:0]      enqueue_store_address_i;
  logic [$bits(DATA)-1:0]      enqueue_store_data_i;
  logic [($bits(DATA)/8)-1:0]  enqueue_store_byte_enable_i;
  logic                        enqueue_accepted_o;

  logic                        dequeue_request_i;
  logic [$bits(ADDR)-1:0]      dequeue_store_address_o;
  logic [$bits(DATA)-1:0]      dequeue_store_data_o;
  logic [($bits(DATA)/8)-1:0]  dequeue_store_byte_enable_o;
  logic                        dequeue_accepted_o;

  // ---------- Instantiate DUT ----------
  store_queue_fifo dut (
    .clock(clock),
    .reset(reset),

    .enqueue_request_i(enqueue_request_i),
    .enqueue_store_address_i(enqueue_store_address_i),
    .enqueue_store_data_i(enqueue_store_data_i),
    .enqueue_store_byte_enable_i(enqueue_store_byte_enable_i),
    .enqueue_accepted_o(enqueue_accepted_o),

    .dequeue_request_i(dequeue_request_i),
    .dequeue_store_address_o(dequeue_store_address_o),
    .dequeue_store_data_o(dequeue_store_data_o),
    .dequeue_store_byte_enable_o(dequeue_store_byte_enable_o),
    .dequeue_accepted_o(dequeue_accepted_o)
  );

  // ---------- Golden model ----------
  store_queue_entry_t ref_q[$];

  // ---------- Helpers ----------
  task automatic drive_idle();
    enqueue_request_i           = 1'b0;
    enqueue_store_address_i     = '0;
    enqueue_store_data_i        = '0;
    enqueue_store_byte_enable_i = '0;
    dequeue_request_i           = 1'b0;
  endtask

  // Assert enqueue until accepted; mirror to ref_q when acked
  task automatic enqueue_wait(input ADDR a, input DATA d, input logic [($bits(DATA)/8)-1:0] be);
    enqueue_store_address_i     = a;
    enqueue_store_data_i        = d;
    enqueue_store_byte_enable_i = be;
    enqueue_request_i           = 1'b1;
    do @(posedge clock); while (!enqueue_accepted_o);
    ref_q.push_back('{store_address:a, store_data:d, store_byte_enable:be});
    enqueue_request_i = 1'b0;
    @(posedge clock);
  endtask

  // Assert dequeue until accepted; compare with front of ref_q
  task automatic dequeue_wait_and_check();
    store_queue_entry_t exp;
    if (ref_q.size() == 0) $fatal(1, "[TB] Dequeue requested but model is empty.");
    dequeue_request_i = 1'b1;
    do @(posedge clock); while (!dequeue_accepted_o);
    //store_queue_entry_t exp = ref_q.pop_front();
    exp = ref_q.pop_front();


    if (dequeue_store_address_o      !== exp.store_address)
      $fatal(1, "[TB] Addr mismatch exp=%h got=%h", exp.store_address, dequeue_store_address_o);
    if (dequeue_store_data_o         !== exp.store_data)
      $fatal(1, "[TB] Data mismatch exp=%h got=%h", exp.store_data, dequeue_store_data_o);
    if (dequeue_store_byte_enable_o  !== exp.store_byte_enable)
      $fatal(1, "[TB] BE mismatch   exp=%b got=%b", exp.store_byte_enable, dequeue_store_byte_enable_o);

    dequeue_request_i = 1'b0;
    @(posedge clock);
  endtask

  // Deterministic payloads
  function automatic store_queue_entry_t mk_entry(input int seed);
    store_queue_entry_t e;
    e.store_address     = ADDR'(32'h1000 + seed*4);
    e.store_data        = DATA'(seed ^ (seed << 5));              // pseudo-data for 32-bit DATA
    e.store_byte_enable = {($bits(DATA)/8){1'b1}};                // all bytes enabled
    return e;
  endfunction

  // ---------- Tests ----------
  initial begin
    $display("---- store_queue_fifo TB ----");
    drive_idle();
    apply_reset();

    // T1: Basic order
    $display("[T1] Basic enqueue/dequeue...");
    for (int i=0;i<2;i++) begin
      store_queue_entry_t e = mk_entry(i);
      enqueue_wait(e.store_address, e.store_data, e.store_byte_enable);
    end
    for (int i=0;i<2;i++) begin
      dequeue_wait_and_check();
    end
    $display("[T1] PASS.");

    // T2: Wrap-around (with your `LSQ_SZ`=8 by default)
    $display("[T2] Wrap-around...");
    for (int i=0;i<`LSQ_SZ;i++) begin
      store_queue_entry_t e = mk_entry(100+i);
      enqueue_wait(e.store_address, e.store_data, e.store_byte_enable);
    end
    // Dequeue 1
    dequeue_wait_and_check();
    // Enqueue one more (forces tail wrap if it was at last index)
    store_queue_entry_t ewrap = mk_entry(200);
    enqueue_wait(ewrap.store_address, ewrap.store_data, ewrap.store_byte_enable);
    // Drain remaining
    while (ref_q.size()>0) dequeue_wait_and_check();
    $display("[T2] PASS.");

    // T3: Full + same-cycle enq+deq
    $display("[T3] Full + same-cycle enqueue+dequeue...");
    store_queue_entry_t exp;
    exp = ref_q.pop_front();
    for (int i=0;i<`LSQ_SZ;i++) begin
      store_queue_entry_t e = mk_entry(300+i);
      enqueue_wait(e.store_address, e.store_data, e.store_byte_enable);
    end
    

    store_queue_entry_t enext = mk_entry(999);

    // Drive both requests before the edge
    enqueue_store_address_i     = enext.store_address;
    enqueue_store_data_i        = enext.store_data;
    enqueue_store_byte_enable_i = enext.store_byte_enable;
    enqueue_request_i           = 1'b1;
    dequeue_request_i           = 1'b1;

    @(posedge clock);

    if (!dequeue_accepted_o || !enqueue_accepted_o) begin
      $display("enqueue_accepted_o=%0b dequeue_accepted_o=%0b",
               enqueue_accepted_o,     dequeue_accepted_o);
      $fatal(1, "[T3] Expected both acks when full and both requests asserted.");
    end

    // Check the dequeued element now and update model
    //store_queue_entry_t exp = ref_q.pop_front();

    if (dequeue_store_address_o !== exp.store_address ||
        dequeue_store_data_o    !== exp.store_data    ||
        dequeue_store_byte_enable_o !== exp.store_byte_enable) begin
      $fatal(1, "[T3] Same-cycle mismatch.");
    end
    ref_q.push_back(enext);

    // Deassert requests and drain
    enqueue_request_i = 1'b0;
    dequeue_request_i = 1'b0;
    @(posedge clock);
    while (ref_q.size()>0) dequeue_wait_and_check();
    $display("[T3] PASS.");

    $display("All tests PASS ✅");
    $finish;
  end

endmodule

`default_nettype wire
