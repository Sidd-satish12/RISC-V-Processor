    li t0, 0
    la t1, btt6
    jalr t0,t1,0
linkaddr:
    wfi
btt6:
    la t1, linkaddr
    bne t0, t1, linkaddr
    wfi