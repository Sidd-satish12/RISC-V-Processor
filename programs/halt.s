    addi x1, x0, 5      # x1 = 5
    addi x2, x0, 0      # x2 = 0
    beq  x1, x0, skip   # if x1 == 0, skip next instruction (should NOT branch)
    addi x2, x2, 1      # x2 = x2 + 1 (should execute)
skip:
    addi x1, x1, -1     # x1 = x1 - 1
    bne x1, x0, skip       # if x1 != 0, branch to loop (here we treat next instruction as loop)
    wfi                  # end

    

