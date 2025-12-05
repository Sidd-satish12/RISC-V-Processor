data = 0x3E80

    li    x30, 30
    li    x31, 31

end:    li    x21, data
    sw    x30,  0(x21)
    sw    x31,  8(x21)
    wfi