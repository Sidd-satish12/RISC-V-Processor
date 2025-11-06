# Setup some registers
addi x1, x0, 5       # x1 = 5
addi x2, x0, 10      # x2 = 10
addi x3, x0, 0       # x3 = 0 (branch target accumulator)

# Compare x1 and x2 -> branch not taken
bne x1, x2, label1   # x1 != x2, branch should be taken to label1
addi x3, x0, 1       # This should be skipped if branch works

label1:
addi x3, x3, 2       # x3 = 2

# Compare x1 and x1 -> branch not taken
bne x1, x1, label2   # x1 == x1, branch not taken
addi x3, x3, 4       # x3 = 6 (if branch is correct, we execute this)
label2:
addi x3, x3, 8       # x3 = 14 at the end
