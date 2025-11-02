/*
  Basic test program with non-dependent ADD operations
  Tests out-of-order execution of independent instructions
*/

    li	x1, 10       # Load 10 into x1
    li	x2, 20       # Load 20 into x2
    li	x3, 30       # Load 30 into x3
    li	x4, 40       # Load 40 into x4

    add	x5, x1, x2   # x5 = 10 + 20 = 30
    add	x6, x3, x4   # x6 = 30 + 40 = 70 (independent of above)
    add	x7, x1, x3   # x7 = 10 + 30 = 40 (independent)
    add	x8, x2, x4   # x8 = 20 + 40 = 60 (independent)

    add	x9, x5, x6   # x9 = 30 + 70 = 100 (depends on x5,x6)
    add	x10, x7, x8  # x10 = 40 + 60 = 100 (depends on x7,x8)

    add	x11, x9, x10 # x11 = 100 + 100 = 200 (final result)
    wfi              # Halt the processor

