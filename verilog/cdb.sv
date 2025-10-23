module cdb (
  parameter int N = `N  // CDB width == superscalar width
)(
  input  logic                  clock,
  input  logic                  reset,

  // From Execute/Complete: up to N results this cycle (present <= N!)
  input  logic     [N-1:0]      comp_valid,
  input  PHYS_TAG  [N-1:0]      comp_tag,

  // Early-tag grant (COMBINATIONAL): which inputs "made" the CDB this cycle
  output logic     [N-1:0]      comp_grant,

  // Registered 1-cycle broadcast to consumers (RS / Map Table)
  output CDB_PACKET             cdb_to_rs,
  output logic     [N-1:0]      cdb_valid_to_mt,
  output PHYS_TAG  [N-1:0]      cdb_tag_to_mt
);
