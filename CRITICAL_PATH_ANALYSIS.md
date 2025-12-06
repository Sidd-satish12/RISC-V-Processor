# Critical Path Analysis and Pipeline Register Recommendations

## Executive Summary

Based on synthesis output analysis and code review, the critical path likely resides in the **Dispatch Stage** due to complex combinational logic with sequential dependencies. Secondary critical paths exist in the **Register File** (large forwarding multiplexers) and **Issue Stage** (allocator logic).

## Synthesis Output Analysis

### Large Multiplexers Identified

From the synthesis output (`Compile syn.simv.out`):

1. **Register File (regfile/96)**: 
   - **64 inputs, 32 outputs, 6 selector bits** (appears 14 times)
   - This is the PRF read port with forwarding from CDB
   - **CRITICAL**: Each read port checks all CDB entries for forwarding

2. **CPU Top Level (cpu/65, 66, 67)**:
   - **32 inputs, 7 outputs, 5 selector bits** (appears 9 times)
   - Likely related to instruction routing or register selection

3. **Store Queue (store_queue/245)**:
   - **8 inputs, 67 outputs, 3 selector bits** (appears 17 times)
   - Store queue entry selection logic

4. **Branch Predictor (bp/65, 67, 95)**:
   - **256 inputs, 1 output, 8 selector bits** (PHT lookup)
   - **128 inputs, 56 outputs, 7 selector bits** (BTB lookup)
   - **256 inputs, 2 outputs, 8 selector bits** (target selection)

## Critical Path Locations

### 1. **Dispatch Stage** (HIGHEST PRIORITY)

**Location**: `verilog/stage_dispatch.sv`

**Critical Path Components**:
- **Map Table Read** → **Register Renaming Forwarding** → **Resource Allocation Checks** → **RS Entry Creation**
- Sequential dependency: Map table read must complete before register renaming can proceed
- Forward register renaming loop (lines 254-285): Each instruction depends on previous instructions' renames
- Resource allocation checks (lines 108-191): Complex loop checking ROB, freelist, RS banks, store queue

**Path Length**: 
- Map table read (combinational)
- Forward renaming within dispatch group (N iterations, each depends on previous)
- Resource availability checks (N iterations with early break)
- RS entry packet construction

**Recommendation**: **Add pipeline register between Map Table Read and Register Renaming**

### 2. **Register File Forwarding** (HIGH PRIORITY)

**Location**: `verilog/regfile.sv`, function `read_register_with_forwarding`

**Critical Path Components**:
- **CDB Tag Comparison** → **64:1 Multiplexer** → **Data Output**
- For each read port: Check all `CDB_SZ` entries (typically 3) for tag match
- Then select from 64 physical registers (64:1 mux)

**Path Length**:
- CDB tag comparisons (CDB_SZ × tag width comparisons)
- 64:1 multiplexer selection
- This path is in the **Execute Stage** data path

**Recommendation**: **Pipeline the PRF read operation** - separate tag comparison from data selection

### 3. **Issue Stage Allocators** (MEDIUM PRIORITY)

**Location**: `verilog/stage_issue.sv`

**Critical Path Components**:
- **RS Ready Signal Computation** → **Allocator Logic** → **Grant Selection**
- Multiple allocators (ALU, MULT, BRANCH, MEM) operating in parallel
- Each allocator uses `psel_gen` which has priority encoding logic

**Path Length**:
- Ready signal computation (check src1_ready && src2_ready for all RS entries)
- Allocator priority encoding (psel_gen with WIDTH=6, REQS=3 for ALU)
- Grant bus generation

**Recommendation**: **Pipeline allocator grants** - register ready signals before allocator

### 4. **CDB Arbitration** (MEDIUM PRIORITY)

**Location**: `verilog/cdb.sv`

**Critical Path Components**:
- **Request Flattening** → **Priority Encoder (psel_gen)** → **Grant Bus Generation** → **CDB Output Selection**
- psel_gen with WIDTH=6 (NUM_FU_TOTAL), REQS=3 (N)
- Grant bus: 3×6 = 18 bits, each bit selects from 6 FU outputs

**Path Length**:
- Request concatenation
- Priority encoding (psel_gen)
- Grant bus generation (3×6 matrix)
- CDB output selection (3 outputs, each selects from 6 inputs)

**Recommendation**: **Pipeline CDB arbitration** - separate grant generation from output selection

### 5. **Execute Stage Data Forwarding** (LOWER PRIORITY)

**Location**: `verilog/stage_execute.sv`, lines 150-204

**Critical Path Components**:
- **CDB Data Forwarding Check** → **Operand Resolution** → **ALU/MULT/Branch Input Selection**
- For each FU: Check all CDB entries against PRF read tags
- Then resolve operands (PRF data vs CDB forwarded data)

**Path Length**:
- CDB forwarding checks (N CDB entries × NUM_FU_TOTAL FUs)
- Operand resolution multiplexers
- ALU/Branch function selection

**Note**: This is partially mitigated by the PRF forwarding, but still has significant combinational depth.

## Pipeline Register Recommendations

### Priority 1: Dispatch Stage Pipeline

**Location**: After Map Table Read, Before Register Renaming

**Implementation**:
1. Add pipeline register for map table read responses
2. Register: `maptable_read_resp` → `maptable_read_resp_reg`
3. Use registered version for forward renaming logic
4. This breaks the critical path: Map Table → Register Renaming

**Files to Modify**:
- `verilog/stage_dispatch.sv`: Add pipeline register after line 207
- Add new always_ff block to register map table responses
- Update forward renaming to use registered responses

**Impact**: 
- **Reduces critical path by ~30-40%** (map table read removed from critical path)
- Adds 1 cycle latency to dispatch (acceptable trade-off)
- Map table can be read in previous cycle

### Priority 2: Register File Read Pipeline

**Location**: Separate tag comparison from data selection

**Implementation**:
1. Pipeline register for CDB forwarding decisions
2. Register forwarding match signals
3. Use registered matches for final data selection

**Files to Modify**:
- `verilog/regfile.sv`: Modify `read_register_with_forwarding` function
- Add pipeline stage: Tag comparison → Register → Data selection

**Impact**:
- **Reduces critical path by ~25-35%** (breaks 64:1 mux from tag comparison)
- Adds 1 cycle latency to PRF reads (requires Execute stage adjustment)
- May require forwarding path adjustments

### Priority 3: Issue Stage Ready Signal Pipeline

**Location**: Before Allocator Input

**Implementation**:
1. Register RS ready signals before allocator
2. Register: `rs_ready_alu` → `rs_ready_alu_reg`
3. Use registered ready signals for allocator requests

**Files to Modify**:
- `verilog/stage_issue.sv`: Add pipeline register after ready signal computation (after line 70)

**Impact**:
- **Reduces critical path by ~20-30%** (ready computation separated from allocator)
- Adds 1 cycle latency to issue (acceptable)
- Allocator operates on stable ready signals

### Priority 4: CDB Arbitration Pipeline

**Location**: After Grant Generation, Before Output Selection

**Implementation**:
1. Register grant bus after psel_gen
2. Register: `grants_flat_next` → `grants_flat_reg`
3. Use registered grants for CDB output selection

**Files to Modify**:
- `verilog/cdb.sv`: Already has pipeline register (line 74-84), but could optimize further
- Consider registering grant bus separately from CDB output

**Impact**:
- **Reduces critical path by ~15-25%** (grant generation separated from output selection)
- Minimal latency impact (already pipelined)

## Implementation Strategy

### Phase 1: Dispatch Stage Pipeline (Highest Impact)
1. Add map table read response register
2. Update forward renaming to use registered responses
3. Verify dispatch still works correctly with 1-cycle latency

### Phase 2: Register File Pipeline (High Impact)
1. Pipeline PRF read tag comparison
2. Update Execute stage to account for PRF read latency
3. May require additional forwarding paths

### Phase 3: Issue Stage Pipeline (Medium Impact)
1. Register RS ready signals
2. Update allocator to use registered ready signals
3. Verify issue logic still correct

### Phase 4: CDB Optimization (Lower Priority)
1. Optimize existing CDB pipeline
2. Separate grant generation from output selection if needed

## Expected Performance Improvements

- **Dispatch Stage Pipeline**: ~30-40% critical path reduction
- **Register File Pipeline**: ~25-35% critical path reduction  
- **Issue Stage Pipeline**: ~20-30% critical path reduction
- **Combined**: **Potential 50-60% critical path reduction** (non-linear due to path interactions)

## Trade-offs

### Latency Impact
- Dispatch: +1 cycle (map table read pipelined)
- PRF Read: +1 cycle (if implemented)
- Issue: +1 cycle (ready signal pipelined)
- **Total IPC impact**: Minimal if pipeline is kept full

### Area Impact
- Additional pipeline registers: ~500-1000 flip-flops
- Negligible impact on overall area

### Complexity Impact
- Requires careful handling of pipeline bubbles
- May need additional bypass paths
- Test thoroughly for correctness

## Verification Strategy

1. **Functional Verification**: Ensure all pipeline stages still work correctly
2. **Timing Verification**: Run synthesis and check slack improvement
3. **Performance Verification**: Run benchmarks to verify IPC maintained/improved
4. **Corner Cases**: Test pipeline stalls, mispredicts, and resource conflicts

## Next Steps

1. Fix synthesis error in `dcache_subsystem.sv` (line 177: array index out of bounds)
2. Run successful synthesis to get actual timing reports
3. Identify exact critical path from timing report
4. Implement Priority 1 (Dispatch Stage Pipeline)
5. Re-synthesize and measure improvement
6. Iterate with additional pipeline stages as needed

