// Pseudo Tree LRU module for cache replacement policy
// Uses a binary tree structure with N-1 bits to track LRU state
// Each bit indicates which subtree is LRU (0 = left, 1 = right)
// Only tracks write operations to avoid race conditions
module pseudo_tree_lru #(
    parameter CACHE_SIZE = `DCACHE_LINES,
    parameter INDEX_BITS = $clog2(CACHE_SIZE)
) (
    input clock,
    input reset,

    // Write access update interface
    input logic [INDEX_BITS-1:0] write_index,    // Cache line index written
    input logic                  write_valid,    // Whether write occurred

    // LRU output
    output logic [INDEX_BITS-1:0] lru_index     // Index of least recently used cache line
);

    // Tree structure: for N cache lines, we need N-1 internal nodes
    // Each node stores 1 bit indicating which subtree is LRU (0=left, 1=right)
    localparam TREE_NODES = CACHE_SIZE - 1;
    localparam TREE_NODE_BITS = $clog2(TREE_NODES + CACHE_SIZE + 1);  // Bits needed for tree node indices
    
    logic [TREE_NODES-1:0] lru_tree, next_lru_tree;
    
    // Parallel path calculation signals
    logic [TREE_NODES-1:0] w_mask,  w_val;   // Write update mask and values
    
    // LRU traversal variable
    logic [TREE_NODE_BITS-1:0] node_idx;

    // Helper function to calculate update path masks and values
    // This is purely combinational logic, executed in parallel
    function automatic void get_update_path(
        input logic [INDEX_BITS-1:0] idx,
        input logic valid,
        output logic [TREE_NODES-1:0] mask,
        output logic [TREE_NODES-1:0] val
    );
        logic [TREE_NODE_BITS-1:0] node_idx;
        logic [TREE_NODE_BITS-1:0] parent_idx;
        
        mask = '0;
        val  = '0;
        
        if (valid) begin
            node_idx = TREE_NODES + idx;
            
            // Traverse from leaf to root, calculating which nodes need updates
            for (int i = 0; i < INDEX_BITS; i++) begin
                if (node_idx > 0) begin
                    parent_idx = (node_idx - 1) >> 1;
                    if (parent_idx < TREE_NODES) begin
                        mask[parent_idx] = 1'b1;  // Mark this node as affected
                        
                        // Set value: Right child (even) accessed -> set parent to 0 (left subtree becomes LRU)
                        //            Left child (odd) accessed -> set parent to 1 (right subtree becomes LRU)
                        if ((node_idx & 1) == 0) begin
                            // Right child (even): set parent to 0 (left subtree becomes LRU, right is MRU)
                            val[parent_idx] = 1'b0;
                        end else begin
                            // Left child (odd): set parent to 1 (right subtree becomes LRU, left is MRU)
                            val[parent_idx] = 1'b1;
                        end
                        
                        node_idx = parent_idx;
                    end
                end
            end
        end
    endfunction

    always_comb begin
        get_update_path(write_index, write_valid, w_mask, w_val);
    end

    always_comb begin
        for (int i = 0; i < TREE_NODES; i++) begin
            if (w_mask[i]) begin
                next_lru_tree[i] = w_val[i];
            end else begin
                next_lru_tree[i] = lru_tree[i];
            end
        end
    end

    // Find LRU index by traversing the tree from root to leaf
    always_comb begin
        lru_index = '0;
        node_idx = '0;
        
        // Traverse tree from root (node 0) to leaf following LRU bits
        for (int level = 0; level < INDEX_BITS; level++) begin
            if (node_idx < TREE_NODES) begin
                if (lru_tree[node_idx]) begin
                    // Right subtree is LRU, go right
                    node_idx = (node_idx << 1) + 2;  // Right child: 2*node + 2
                end else begin
                    // Left subtree is LRU, go left
                    node_idx = (node_idx << 1) + 1;  // Left child: 2*node + 1
                end
            end
        end
        
        // Convert final tree node index to cache line index
        // Cache index = leaf_node_index - TREE_NODES
        lru_index = INDEX_BITS'(node_idx - TREE_NODES);
    end

    // Sequential State Update
    always_ff @(posedge clock) begin
        if (reset) begin
            lru_tree <= '0;  // Initialize: all bits 0 means left subtrees are LRU
        end else begin
            lru_tree <= next_lru_tree;
        end
    end

endmodule