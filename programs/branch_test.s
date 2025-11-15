/*
  Simple branch test program using bne instruction
  Tests basic branching functionality in a loop
*/
    li   x1, 0        # Initialize counter to 0
    li   x2, 1000     # Loop limit (many iterations for BP testing)
loop:
    addi x1, x1, 1    # Increment counter
    bne  x1, x2, loop # Branch back if x1 != x2
    # Loop exits when x1 == x2 (counter reaches 1000)
    # This provides many branch iterations for BP training
    wfi               # End program
