	.file	"alexnet.c"
	.option nopic
	.option norelax
	.attribute arch, "rv32i2p0_m2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.local	heap
	.comm	heap,16384,4
	.section	.sdata,"aw"
	.align	2
	.type	next_index, @object
	.size	next_index, 4
next_index:
	.word	heap
	.align	2
	.type	avail_mem, @object
	.size	avail_mem, 4
avail_mem:
	.word	16384
	.local	base
	.comm	base,8,4
	.local	freep
	.comm	freep,4,4
	.text
	.align	2
	.globl	tj_free
	.type	tj_free, @function
tj_free:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	lw	a4,-36(s0)
	lui	a5,%hi(heap)
	addi	a5,a5,%lo(heap)
	bltu	a4,a5,.L2
	lui	a5,%hi(heap+16384)
	addi	a5,a5,%lo(heap+16384)
	lw	a4,-36(s0)
	bleu	a4,a5,.L3
.L2:
	li	a0,1
	call	exit
.L3:
	lw	a5,-36(s0)
	addi	a5,a5,-8
	sw	a5,-24(s0)
	lui	a5,%hi(freep)
	lw	a5,%lo(freep)(a5)
	sw	a5,-20(s0)
	j	.L4
.L7:
	lw	a5,-20(s0)
	lw	a5,0(a5)
	lw	a4,-20(s0)
	bltu	a4,a5,.L5
	lw	a4,-24(s0)
	lw	a5,-20(s0)
	bgtu	a4,a5,.L6
	lw	a5,-20(s0)
	lw	a5,0(a5)
	lw	a4,-24(s0)
	bltu	a4,a5,.L6
.L5:
	lw	a5,-20(s0)
	lw	a5,0(a5)
	sw	a5,-20(s0)
.L4:
	lw	a4,-24(s0)
	lw	a5,-20(s0)
	bleu	a4,a5,.L7
	lw	a5,-20(s0)
	lw	a5,0(a5)
	lw	a4,-24(s0)
	bgeu	a4,a5,.L7
.L6:
	lw	a5,-24(s0)
	lw	a5,4(a5)
	slli	a5,a5,3
	lw	a4,-24(s0)
	add	a4,a4,a5
	lw	a5,-20(s0)
	lw	a5,0(a5)
	bne	a4,a5,.L8
	lw	a5,-24(s0)
	lw	a4,4(a5)
	lw	a5,-20(s0)
	lw	a5,0(a5)
	lw	a5,4(a5)
	add	a4,a4,a5
	lw	a5,-24(s0)
	sw	a4,4(a5)
	lw	a5,-20(s0)
	lw	a5,0(a5)
	lw	a4,0(a5)
	lw	a5,-24(s0)
	sw	a4,0(a5)
	j	.L9
.L8:
	lw	a5,-20(s0)
	lw	a4,0(a5)
	lw	a5,-24(s0)
	sw	a4,0(a5)
.L9:
	lw	a5,-20(s0)
	lw	a5,4(a5)
	slli	a5,a5,3
	lw	a4,-20(s0)
	add	a5,a4,a5
	lw	a4,-24(s0)
	bne	a4,a5,.L10
	lw	a5,-20(s0)
	lw	a4,4(a5)
	lw	a5,-24(s0)
	lw	a5,4(a5)
	add	a4,a4,a5
	lw	a5,-20(s0)
	sw	a4,4(a5)
	lw	a5,-24(s0)
	lw	a4,0(a5)
	lw	a5,-20(s0)
	sw	a4,0(a5)
	j	.L11
.L10:
	lw	a5,-20(s0)
	lw	a4,-24(s0)
	sw	a4,0(a5)
.L11:
	lui	a5,%hi(freep)
	lw	a4,-20(s0)
	sw	a4,%lo(freep)(a5)
	nop
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	tj_free, .-tj_free
	.align	2
	.type	getmoremem, @function
getmoremem:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	lui	a5,%hi(avail_mem)
	lw	a5,%lo(avail_mem)(a5)
	lw	a4,-36(s0)
	bleu	a4,a5,.L13
	li	a5,0
	j	.L14
.L13:
	lui	a5,%hi(next_index)
	lw	a5,%lo(next_index)(a5)
	sw	a5,-20(s0)
	lui	a5,%hi(next_index)
	lw	a4,%lo(next_index)(a5)
	lw	a5,-36(s0)
	add	a4,a4,a5
	lui	a5,%hi(next_index)
	sw	a4,%lo(next_index)(a5)
	lui	a5,%hi(avail_mem)
	lw	a4,%lo(avail_mem)(a5)
	lw	a5,-36(s0)
	sub	a4,a4,a5
	lui	a5,%hi(avail_mem)
	sw	a4,%lo(avail_mem)(a5)
	lw	a5,-36(s0)
	addi	a4,a5,-8
	lw	a5,-20(s0)
	sw	a4,4(a5)
	lw	a5,-20(s0)
	addi	a5,a5,8
	sw	a5,-20(s0)
	lw	a0,-20(s0)
	call	tj_free
	lui	a5,%hi(freep)
	lw	a5,%lo(freep)(a5)
.L14:
	mv	a0,a5
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	getmoremem, .-getmoremem
	.align	2
	.globl	tj_malloc
	.type	tj_malloc, @function
tj_malloc:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	lw	a4,-36(s0)
	li	a5,16384
	bleu	a4,a5,.L16
	li	a5,0
	j	.L17
.L16:
	lw	a5,-36(s0)
	andi	a5,a5,3
	beq	a5,zero,.L18
	lw	a5,-36(s0)
	andi	a5,a5,-4
	addi	a5,a5,4
	sw	a5,-36(s0)
.L18:
	lw	a5,-36(s0)
	addi	a5,a5,8
	sw	a5,-28(s0)
	lui	a5,%hi(freep)
	lw	a5,%lo(freep)(a5)
	sw	a5,-24(s0)
	lw	a5,-24(s0)
	bne	a5,zero,.L19
	lui	a5,%hi(base)
	addi	a5,a5,%lo(base)
	sw	a5,-24(s0)
	lui	a5,%hi(freep)
	lw	a4,-24(s0)
	sw	a4,%lo(freep)(a5)
	lui	a5,%hi(freep)
	lw	a4,%lo(freep)(a5)
	lui	a5,%hi(base)
	addi	a5,a5,%lo(base)
	sw	a4,0(a5)
	lui	a5,%hi(base)
	addi	a5,a5,%lo(base)
	sw	zero,4(a5)
.L19:
	lw	a5,-24(s0)
	lw	a5,0(a5)
	sw	a5,-20(s0)
.L24:
	lw	a5,-20(s0)
	lw	a5,4(a5)
	lw	a4,-36(s0)
	bgtu	a4,a5,.L20
	lw	a5,-20(s0)
	lw	a5,4(a5)
	lw	a4,-36(s0)
	bne	a4,a5,.L21
	lw	a5,-20(s0)
	lw	a4,0(a5)
	lw	a5,-24(s0)
	sw	a4,0(a5)
	j	.L22
.L21:
	lw	a5,-20(s0)
	lw	a4,4(a5)
	lw	a5,-28(s0)
	sub	a4,a4,a5
	lw	a5,-20(s0)
	sw	a4,4(a5)
	lw	a5,-20(s0)
	lw	a5,4(a5)
	slli	a5,a5,3
	lw	a4,-20(s0)
	add	a5,a4,a5
	sw	a5,-20(s0)
	lw	a5,-20(s0)
	lw	a4,-36(s0)
	sw	a4,4(a5)
.L22:
	lui	a5,%hi(freep)
	lw	a4,-24(s0)
	sw	a4,%lo(freep)(a5)
	lw	a5,-20(s0)
	addi	a5,a5,8
	sw	a5,-20(s0)
	lw	a5,-20(s0)
	j	.L17
.L20:
	lui	a5,%hi(freep)
	lw	a5,%lo(freep)(a5)
	lw	a4,-20(s0)
	bne	a4,a5,.L23
	lw	a0,-28(s0)
	call	getmoremem
	sw	a0,-20(s0)
	lw	a5,-20(s0)
	bne	a5,zero,.L23
	li	a5,0
	j	.L17
.L23:
	lw	a5,-20(s0)
	sw	a5,-24(s0)
	lw	a5,-20(s0)
	lw	a5,0(a5)
	sw	a5,-20(s0)
	j	.L24
.L17:
	mv	a0,a5
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	tj_malloc, .-tj_malloc
	.align	2
	.globl	tj_calloc
	.type	tj_calloc, @function
tj_calloc:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	lw	a0,-36(s0)
	call	tj_malloc
	sw	a0,-20(s0)
	lw	a2,-36(s0)
	li	a1,0
	lw	a0,-20(s0)
	call	memset
	lw	a5,-20(s0)
	mv	a0,a5
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	tj_calloc, .-tj_calloc
	.globl	lfsr
	.section	.sdata
	.align	2
	.type	lfsr, @object
	.size	lfsr, 4
lfsr:
	.word	44257
	.globl	period
	.section	.sbss,"aw",@nobits
	.align	2
	.type	period, @object
	.size	period, 4
period:
	.zero	4
	.comm	s,17,4
	.text
	.align	2
	.globl	random_gen
	.type	random_gen, @function
random_gen:
	addi	sp,sp,-32
	sw	s0,28(sp)
	addi	s0,sp,32
	lui	a5,%hi(lfsr)
	lw	a5,%lo(lfsr)(a5)
	andi	a5,a5,1
	sw	a5,-20(s0)
	lui	a5,%hi(lfsr)
	lw	a5,%lo(lfsr)(a5)
	srli	a4,a5,1
	lui	a5,%hi(lfsr)
	sw	a4,%lo(lfsr)(a5)
	lw	a4,-20(s0)
	li	a5,1
	bne	a4,a5,.L28
	lui	a5,%hi(lfsr)
	lw	a4,%lo(lfsr)(a5)
	li	a5,45056
	addi	a5,a5,1024
	xor	a4,a4,a5
	lui	a5,%hi(lfsr)
	sw	a4,%lo(lfsr)(a5)
.L28:
	lui	a5,%hi(lfsr)
	lw	a5,%lo(lfsr)(a5)
	mv	a0,a5
	lw	s0,28(sp)
	addi	sp,sp,32
	jr	ra
	.size	random_gen, .-random_gen
	.align	2
	.globl	relu_af
	.type	relu_af, @function
relu_af:
	addi	sp,sp,-32
	sw	s0,28(sp)
	addi	s0,sp,32
	sw	a0,-20(s0)
	lw	a5,-20(s0)
	bge	a5,zero,.L31
	li	a5,0
	j	.L32
.L31:
	lw	a5,-20(s0)
.L32:
	mv	a0,a5
	lw	s0,28(sp)
	addi	sp,sp,32
	jr	ra
	.size	relu_af, .-relu_af
	.align	2
	.globl	fc_layer
	.type	fc_layer, @function
fc_layer:
	addi	sp,sp,-64
	sw	ra,60(sp)
	sw	s0,56(sp)
	sw	s1,52(sp)
	addi	s0,sp,64
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	a2,-44(s0)
	sw	a3,-48(s0)
	sw	a4,-52(s0)
	sw	a5,-56(s0)
	sw	a6,-60(s0)
	sw	zero,-20(s0)
	j	.L34
.L40:
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a4,-40(s0)
	add	a4,a4,a5
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a3,-48(s0)
	add	a5,a3,a5
	lw	a4,0(a4)
	sw	a4,0(a5)
	sw	zero,-24(s0)
	j	.L35
.L36:
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a4,-48(s0)
	add	a5,a4,a5
	lw	a3,0(a5)
	lw	a4,-20(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	slli	a5,a5,2
	mv	a4,a5
	lw	a5,-36(s0)
	add	a4,a5,a4
	lw	a5,-24(s0)
	slli	a5,a5,2
	add	a5,a4,a5
	lw	a4,0(a5)
	lw	a5,-24(s0)
	slli	a5,a5,2
	lw	a2,-44(s0)
	add	a5,a2,a5
	lw	a5,0(a5)
	mul	a4,a4,a5
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a2,-48(s0)
	add	a5,a2,a5
	add	a4,a3,a4
	sw	a4,0(a5)
	lw	a5,-24(s0)
	addi	a5,a5,1
	sw	a5,-24(s0)
.L35:
	lw	a4,-24(s0)
	lw	a5,-52(s0)
	blt	a4,a5,.L36
	lw	a5,-60(s0)
	beq	a5,zero,.L37
	lw	a4,-60(s0)
	li	a5,1
	beq	a4,a5,.L38
	j	.L39
.L37:
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a4,-48(s0)
	add	a5,a4,a5
	lw	a3,0(a5)
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a4,-48(s0)
	add	s1,a4,a5
	mv	a0,a3
	call	relu_af
	mv	a5,a0
	sw	a5,0(s1)
	j	.L39
.L38:
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a4,-48(s0)
	add	a5,a4,a5
	lw	a3,0(a5)
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a4,-48(s0)
	add	s1,a4,a5
	mv	a0,a3
	call	relu_af
	mv	a5,a0
	sw	a5,0(s1)
	nop
.L39:
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L34:
	lw	a4,-20(s0)
	lw	a5,-56(s0)
	blt	a4,a5,.L40
	nop
	nop
	lw	ra,60(sp)
	lw	s0,56(sp)
	lw	s1,52(sp)
	addi	sp,sp,64
	jr	ra
	.size	fc_layer, .-fc_layer
	.align	2
	.globl	fc_input_generator
	.type	fc_input_generator, @function
fc_input_generator:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	zero,-20(s0)
	j	.L42
.L43:
	call	random_gen
	mv	a5,a0
	andi	a4,a5,15
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a3,-36(s0)
	add	a5,a3,a5
	addi	a4,a4,-5
	sw	a4,0(a5)
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L42:
	lw	a4,-20(s0)
	lw	a5,-40(s0)
	blt	a4,a5,.L43
	nop
	nop
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	fc_input_generator, .-fc_input_generator
	.align	2
	.globl	fc_weight_generator
	.type	fc_weight_generator, @function
fc_weight_generator:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	a2,-44(s0)
	sw	a3,-48(s0)
	sw	zero,-20(s0)
	j	.L45
.L48:
	call	random_gen
	mv	a5,a0
	andi	a4,a5,15
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a3,-40(s0)
	add	a5,a3,a5
	addi	a4,a4,-5
	sw	a4,0(a5)
	sw	zero,-24(s0)
	j	.L46
.L47:
	call	random_gen
	mv	a5,a0
	andi	a2,a5,15
	lw	a4,-20(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	slli	a5,a5,2
	mv	a4,a5
	lw	a5,-36(s0)
	add	a3,a5,a4
	addi	a4,a2,-5
	lw	a5,-24(s0)
	slli	a5,a5,2
	add	a5,a3,a5
	sw	a4,0(a5)
	lw	a5,-24(s0)
	addi	a5,a5,1
	sw	a5,-24(s0)
.L46:
	lw	a4,-24(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L47
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L45:
	lw	a4,-20(s0)
	lw	a5,-48(s0)
	blt	a4,a5,.L48
	nop
	nop
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	fc_weight_generator, .-fc_weight_generator
	.align	2
	.globl	fc_soft_max
	.type	fc_soft_max, @function
fc_soft_max:
	addi	sp,sp,-48
	sw	s0,44(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	zero,-24(s0)
	li	a5,1
	sw	a5,-20(s0)
	j	.L50
.L52:
	lw	a5,-24(s0)
	slli	a5,a5,2
	lw	a4,-36(s0)
	add	a5,a4,a5
	lw	a4,0(a5)
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a3,-36(s0)
	add	a5,a3,a5
	lw	a5,0(a5)
	bge	a4,a5,.L51
	lw	a5,-20(s0)
	sw	a5,-24(s0)
.L51:
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L50:
	lw	a4,-20(s0)
	lw	a5,-40(s0)
	blt	a4,a5,.L52
	lw	a5,-24(s0)
	mv	a0,a5
	lw	s0,44(sp)
	addi	sp,sp,48
	jr	ra
	.size	fc_soft_max, .-fc_soft_max
	.align	2
	.globl	cnn_layer
	.type	cnn_layer, @function
cnn_layer:
	addi	sp,sp,-80
	sw	ra,76(sp)
	sw	s0,72(sp)
	sw	s1,68(sp)
	addi	s0,sp,80
	sw	a0,-52(s0)
	sw	a1,-56(s0)
	sw	a2,-60(s0)
	sw	a3,-64(s0)
	sw	a4,-68(s0)
	sw	a5,-72(s0)
	sw	a6,-76(s0)
	sw	a7,-80(s0)
	lw	a5,4(s0)
	slli	a4,a5,1
	lw	a5,-76(s0)
	add	a4,a4,a5
	lw	a5,-80(s0)
	sub	a4,a4,a5
	lw	a5,0(s0)
	sra	a5,a4,a5
	addi	a5,a5,1
	sw	a5,-44(s0)
	sw	zero,-20(s0)
	j	.L55
.L71:
	sw	zero,-24(s0)
	j	.L56
.L70:
	sw	zero,-28(s0)
	j	.L57
.L69:
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a4,-56(s0)
	add	a5,a4,a5
	lw	a3,-20(s0)
	li	a4,100
	mul	a4,a3,a4
	lw	a3,-64(s0)
	add	a2,a3,a4
	lw	a3,0(a5)
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a2,a5
	sw	a3,0(a5)
	sw	zero,-32(s0)
	j	.L58
.L65:
	sw	zero,-36(s0)
	j	.L59
.L64:
	sw	zero,-40(s0)
	j	.L60
.L63:
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-64(s0)
	add	a3,a4,a5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a3,a5
	lw	a1,0(a5)
	lw	a4,0(s0)
	lw	a5,-24(s0)
	mul	a4,a4,a5
	lw	a5,-36(s0)
	add	a4,a4,a5
	lw	a5,4(s0)
	sub	a5,a4,a5
	blt	a5,zero,.L61
	lw	a4,0(s0)
	lw	a5,-28(s0)
	mul	a4,a4,a5
	lw	a5,-40(s0)
	add	a4,a4,a5
	lw	a5,4(s0)
	sub	a5,a4,a5
	blt	a5,zero,.L61
	lw	a4,0(s0)
	lw	a5,-24(s0)
	mul	a4,a4,a5
	lw	a5,-36(s0)
	add	a4,a4,a5
	lw	a5,4(s0)
	sub	a5,a4,a5
	lw	a4,-76(s0)
	ble	a4,a5,.L61
	lw	a4,0(s0)
	lw	a5,-28(s0)
	mul	a4,a4,a5
	lw	a5,-40(s0)
	add	a4,a4,a5
	lw	a5,4(s0)
	sub	a5,a4,a5
	lw	a4,-76(s0)
	ble	a4,a5,.L61
	lw	a4,-32(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-60(s0)
	add	a3,a4,a5
	lw	a4,0(s0)
	lw	a5,-24(s0)
	mul	a4,a4,a5
	lw	a5,-36(s0)
	add	a4,a4,a5
	lw	a5,4(s0)
	sub	a4,a4,a5
	lw	a2,0(s0)
	lw	a5,-28(s0)
	mul	a2,a2,a5
	lw	a5,-40(s0)
	add	a2,a2,a5
	lw	a5,4(s0)
	sub	a2,a2,a5
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	add	a5,a5,a2
	slli	a5,a5,2
	add	a5,a3,a5
	lw	a2,0(a5)
	lw	a4,-20(s0)
	li	a5,500
	mul	a5,a4,a5
	lw	a4,-52(s0)
	add	a0,a4,a5
	lw	a5,-36(s0)
	lw	a3,-32(s0)
	mv	a4,a5
	slli	a4,a4,2
	add	a4,a4,a5
	mv	a5,a3
	slli	a5,a5,1
	add	a5,a5,a3
	slli	a5,a5,3
	add	a5,a5,a3
	add	a4,a4,a5
	lw	a5,-40(s0)
	add	a5,a4,a5
	slli	a5,a5,2
	add	a5,a0,a5
	lw	a5,0(a5)
	mul	a5,a2,a5
	j	.L62
.L61:
	li	a5,0
.L62:
	lw	a3,-20(s0)
	li	a4,100
	mul	a4,a3,a4
	lw	a3,-64(s0)
	add	a2,a3,a4
	add	a3,a5,a1
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a2,a5
	sw	a3,0(a5)
	lw	a5,-40(s0)
	addi	a5,a5,1
	sw	a5,-40(s0)
.L60:
	lw	a4,-40(s0)
	lw	a5,-80(s0)
	blt	a4,a5,.L63
	lw	a5,-36(s0)
	addi	a5,a5,1
	sw	a5,-36(s0)
.L59:
	lw	a4,-36(s0)
	lw	a5,-80(s0)
	blt	a4,a5,.L64
	lw	a5,-32(s0)
	addi	a5,a5,1
	sw	a5,-32(s0)
.L58:
	lw	a4,-32(s0)
	lw	a5,-68(s0)
	blt	a4,a5,.L65
	lw	a5,8(s0)
	beq	a5,zero,.L66
	lw	a4,8(s0)
	li	a5,1
	beq	a4,a5,.L67
	j	.L68
.L66:
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-64(s0)
	add	a3,a4,a5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a3,a5
	lw	a3,0(a5)
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-64(s0)
	add	s1,a4,a5
	mv	a0,a3
	call	relu_af
	mv	a3,a0
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,s1,a5
	sw	a3,0(a5)
	j	.L68
.L67:
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-64(s0)
	add	a3,a4,a5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a3,a5
	lw	a3,0(a5)
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-64(s0)
	add	s1,a4,a5
	mv	a0,a3
	call	relu_af
	mv	a3,a0
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,s1,a5
	sw	a3,0(a5)
	nop
.L68:
	lw	a5,-28(s0)
	addi	a5,a5,1
	sw	a5,-28(s0)
.L57:
	lw	a4,-28(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L69
	lw	a5,-24(s0)
	addi	a5,a5,1
	sw	a5,-24(s0)
.L56:
	lw	a4,-24(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L70
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L55:
	lw	a4,-20(s0)
	lw	a5,-72(s0)
	blt	a4,a5,.L71
	nop
	nop
	lw	ra,76(sp)
	lw	s0,72(sp)
	lw	s1,68(sp)
	addi	sp,sp,80
	jr	ra
	.size	cnn_layer, .-cnn_layer
	.align	2
	.globl	cnn_pool
	.type	cnn_pool, @function
cnn_pool:
	addi	sp,sp,-80
	sw	s0,76(sp)
	addi	s0,sp,80
	sw	a0,-52(s0)
	sw	a1,-56(s0)
	sw	a2,-60(s0)
	sw	a3,-64(s0)
	sw	a4,-68(s0)
	sw	a5,-72(s0)
	sw	a6,-76(s0)
	sw	a7,-80(s0)
	lw	a5,-76(s0)
	slli	a4,a5,1
	lw	a5,-64(s0)
	add	a4,a4,a5
	lw	a5,-68(s0)
	sub	a4,a4,a5
	lw	a5,-72(s0)
	sra	a5,a4,a5
	addi	a5,a5,1
	sw	a5,-40(s0)
	sw	zero,-20(s0)
	j	.L73
.L90:
	sw	zero,-24(s0)
	j	.L74
.L89:
	sw	zero,-28(s0)
	j	.L75
.L88:
	lw	a5,-80(s0)
	beq	a5,zero,.L76
	lw	a4,-80(s0)
	li	a5,1
	beq	a4,a5,.L77
	j	.L78
.L76:
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-52(s0)
	add	a3,a4,a5
	lw	a4,-72(s0)
	lw	a5,-24(s0)
	mul	a4,a4,a5
	lw	a2,-72(s0)
	lw	a5,-28(s0)
	mul	a1,a2,a5
	lw	a2,-20(s0)
	li	a5,100
	mul	a5,a2,a5
	lw	a2,-56(s0)
	add	a2,a2,a5
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	add	a5,a5,a1
	slli	a5,a5,2
	add	a5,a3,a5
	lw	a3,0(a5)
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a2,a5
	sw	a3,0(a5)
	j	.L78
.L77:
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-56(s0)
	add	a3,a4,a5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a3,a5
	sw	zero,0(a5)
	nop
.L78:
	sw	zero,-32(s0)
	j	.L79
.L86:
	sw	zero,-36(s0)
	j	.L80
.L85:
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-52(s0)
	add	a3,a4,a5
	lw	a4,-72(s0)
	lw	a5,-24(s0)
	mul	a4,a4,a5
	lw	a5,-32(s0)
	add	a4,a4,a5
	lw	a2,-72(s0)
	lw	a5,-28(s0)
	mul	a2,a2,a5
	lw	a5,-36(s0)
	add	a2,a2,a5
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	add	a5,a5,a2
	slli	a5,a5,2
	add	a5,a3,a5
	lw	a5,0(a5)
	sw	a5,-44(s0)
	lw	a5,-80(s0)
	beq	a5,zero,.L81
	lw	a4,-80(s0)
	li	a5,1
	beq	a4,a5,.L82
	j	.L83
.L81:
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-56(s0)
	add	a3,a4,a5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a3,a5
	lw	a5,0(a5)
	lw	a3,-20(s0)
	li	a4,100
	mul	a4,a3,a4
	lw	a3,-56(s0)
	add	a2,a3,a4
	lw	a4,-44(s0)
	bge	a4,a5,.L84
	mv	a4,a5
.L84:
	lw	a3,-24(s0)
	mv	a5,a3
	slli	a5,a5,2
	add	a5,a5,a3
	lw	a3,-28(s0)
	add	a5,a5,a3
	slli	a5,a5,2
	add	a5,a2,a5
	sw	a4,0(a5)
	j	.L83
.L82:
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-56(s0)
	add	a3,a4,a5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a3,a5
	lw	a4,0(a5)
	lw	a3,-20(s0)
	li	a5,100
	mul	a5,a3,a5
	lw	a3,-56(s0)
	add	a2,a3,a5
	lw	a5,-44(s0)
	add	a3,a4,a5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a2,a5
	sw	a3,0(a5)
	nop
.L83:
	lw	a5,-36(s0)
	addi	a5,a5,1
	sw	a5,-36(s0)
.L80:
	lw	a4,-36(s0)
	lw	a5,-68(s0)
	blt	a4,a5,.L85
	lw	a5,-32(s0)
	addi	a5,a5,1
	sw	a5,-32(s0)
.L79:
	lw	a4,-32(s0)
	lw	a5,-68(s0)
	blt	a4,a5,.L86
	lw	a4,-80(s0)
	li	a5,1
	bne	a4,a5,.L87
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-56(s0)
	add	a3,a4,a5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a3,a5
	lw	a4,0(a5)
	lw	a5,-68(s0)
	mul	a5,a5,a5
	lw	a2,-20(s0)
	li	a3,100
	mul	a3,a2,a3
	lw	a2,-56(s0)
	add	a2,a2,a3
	sub	a3,a4,a5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a2,a5
	sw	a3,0(a5)
	nop
.L87:
	lw	a5,-28(s0)
	addi	a5,a5,1
	sw	a5,-28(s0)
.L75:
	lw	a4,-28(s0)
	lw	a5,-40(s0)
	blt	a4,a5,.L88
	lw	a5,-24(s0)
	addi	a5,a5,1
	sw	a5,-24(s0)
.L74:
	lw	a4,-24(s0)
	lw	a5,-40(s0)
	blt	a4,a5,.L89
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L73:
	lw	a4,-20(s0)
	lw	a5,-60(s0)
	blt	a4,a5,.L90
	nop
	nop
	lw	s0,76(sp)
	addi	sp,sp,80
	jr	ra
	.size	cnn_pool, .-cnn_pool
	.align	2
	.globl	cnn_input_generator
	.type	cnn_input_generator, @function
cnn_input_generator:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	a2,-44(s0)
	sw	zero,-20(s0)
	j	.L92
.L97:
	sw	zero,-24(s0)
	j	.L93
.L96:
	sw	zero,-28(s0)
	j	.L94
.L95:
	call	random_gen
	mv	a5,a0
	andi	a5,a5,15
	lw	a3,-20(s0)
	li	a4,100
	mul	a4,a3,a4
	lw	a3,-36(s0)
	add	a2,a3,a4
	addi	a3,a5,-5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a2,a5
	sw	a3,0(a5)
	lw	a5,-28(s0)
	addi	a5,a5,1
	sw	a5,-28(s0)
.L94:
	lw	a4,-28(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L95
	lw	a5,-24(s0)
	addi	a5,a5,1
	sw	a5,-24(s0)
.L93:
	lw	a4,-24(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L96
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L92:
	lw	a4,-20(s0)
	lw	a5,-40(s0)
	blt	a4,a5,.L97
	nop
	nop
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	cnn_input_generator, .-cnn_input_generator
	.align	2
	.globl	cnn_weight_generator
	.type	cnn_weight_generator, @function
cnn_weight_generator:
	addi	sp,sp,-64
	sw	ra,60(sp)
	sw	s0,56(sp)
	addi	s0,sp,64
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	a2,-44(s0)
	sw	a3,-48(s0)
	sw	a4,-52(s0)
	sw	zero,-20(s0)
	j	.L99
.L106:
	call	random_gen
	mv	a5,a0
	andi	a4,a5,15
	lw	a5,-20(s0)
	slli	a5,a5,2
	lw	a3,-40(s0)
	add	a5,a3,a5
	addi	a4,a4,-5
	sw	a4,0(a5)
	sw	zero,-24(s0)
	j	.L100
.L105:
	sw	zero,-28(s0)
	j	.L101
.L104:
	sw	zero,-32(s0)
	j	.L102
.L103:
	call	random_gen
	mv	a5,a0
	andi	a5,a5,15
	lw	a3,-20(s0)
	li	a4,500
	mul	a4,a3,a4
	lw	a3,-36(s0)
	add	a1,a3,a4
	addi	a2,a5,-5
	lw	a5,-28(s0)
	lw	a3,-24(s0)
	mv	a4,a5
	slli	a4,a4,2
	add	a4,a4,a5
	mv	a5,a3
	slli	a5,a5,1
	add	a5,a5,a3
	slli	a5,a5,3
	add	a5,a5,a3
	add	a4,a4,a5
	lw	a5,-32(s0)
	add	a5,a4,a5
	slli	a5,a5,2
	add	a5,a1,a5
	sw	a2,0(a5)
	lw	a5,-32(s0)
	addi	a5,a5,1
	sw	a5,-32(s0)
.L102:
	lw	a4,-32(s0)
	lw	a5,-52(s0)
	blt	a4,a5,.L103
	lw	a5,-28(s0)
	addi	a5,a5,1
	sw	a5,-28(s0)
.L101:
	lw	a4,-28(s0)
	lw	a5,-52(s0)
	blt	a4,a5,.L104
	lw	a5,-24(s0)
	addi	a5,a5,1
	sw	a5,-24(s0)
.L100:
	lw	a4,-24(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L105
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L99:
	lw	a4,-20(s0)
	lw	a5,-48(s0)
	blt	a4,a5,.L106
	nop
	nop
	lw	ra,60(sp)
	lw	s0,56(sp)
	addi	sp,sp,64
	jr	ra
	.size	cnn_weight_generator, .-cnn_weight_generator
	.align	2
	.globl	cnn_to_fc
	.type	cnn_to_fc, @function
cnn_to_fc:
	addi	sp,sp,-48
	sw	s0,44(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	sw	a1,-40(s0)
	sw	a2,-44(s0)
	sw	a3,-48(s0)
	sw	zero,-20(s0)
	j	.L108
.L113:
	sw	zero,-24(s0)
	j	.L109
.L112:
	sw	zero,-28(s0)
	j	.L110
.L111:
	lw	a4,-20(s0)
	li	a5,100
	mul	a5,a4,a5
	lw	a4,-36(s0)
	add	a2,a4,a5
	lw	a4,-20(s0)
	lw	a5,-44(s0)
	mul	a4,a4,a5
	lw	a5,-44(s0)
	mul	a4,a4,a5
	lw	a3,-24(s0)
	lw	a5,-44(s0)
	mul	a5,a3,a5
	add	a4,a4,a5
	lw	a5,-28(s0)
	add	a5,a4,a5
	slli	a5,a5,2
	lw	a4,-48(s0)
	add	a3,a4,a5
	lw	a4,-24(s0)
	mv	a5,a4
	slli	a5,a5,2
	add	a5,a5,a4
	lw	a4,-28(s0)
	add	a5,a5,a4
	slli	a5,a5,2
	add	a5,a2,a5
	lw	a5,0(a5)
	sw	a5,0(a3)
	lw	a5,-28(s0)
	addi	a5,a5,1
	sw	a5,-28(s0)
.L110:
	lw	a4,-28(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L111
	lw	a5,-24(s0)
	addi	a5,a5,1
	sw	a5,-24(s0)
.L109:
	lw	a4,-24(s0)
	lw	a5,-44(s0)
	blt	a4,a5,.L112
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L108:
	lw	a4,-20(s0)
	lw	a5,-40(s0)
	blt	a4,a5,.L113
	nop
	nop
	lw	s0,44(sp)
	addi	sp,sp,48
	jr	ra
	.size	cnn_to_fc, .-cnn_to_fc
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-2032
	sw	ra,2028(sp)
	sw	s0,2024(sp)
	addi	s0,sp,2032
	addi	sp,sp,-1728
	sw	zero,-20(s0)
	j	.L115
.L116:
	li	a5,5
	sw	a5,-24(s0)
	li	a5,5
	sw	a5,-28(s0)
	li	a5,5
	sw	a5,-32(s0)
	li	a5,2
	sw	a5,-36(s0)
	li	a5,1
	sw	a5,-40(s0)
	sw	zero,-44(s0)
	li	a5,2
	sw	a5,-48(s0)
	li	a5,-4096
	addi	a5,a5,868
	addi	a4,s0,-16
	add	a5,a4,a5
	lw	a2,-32(s0)
	lw	a1,-28(s0)
	mv	a0,a5
	call	cnn_input_generator
	li	a5,-4096
	addi	a5,a5,1368
	addi	a4,s0,-16
	add	a1,a4,a5
	li	a5,-4096
	addi	a5,a5,1388
	addi	a4,s0,-16
	add	a5,a4,a5
	lw	a4,-36(s0)
	lw	a3,-24(s0)
	lw	a2,-28(s0)
	mv	a0,a5
	call	cnn_weight_generator
	li	a5,-4096
	addi	a5,a5,368
	addi	a4,s0,-16
	add	a3,a4,a5
	li	a5,-4096
	addi	a5,a5,868
	addi	a4,s0,-16
	add	a2,a4,a5
	li	a5,-4096
	addi	a5,a5,1368
	addi	a4,s0,-16
	add	a1,a4,a5
	li	a5,-4096
	addi	a5,a5,1388
	addi	a4,s0,-16
	add	a0,a4,a5
	lw	a5,-48(s0)
	sw	a5,8(sp)
	lw	a5,-44(s0)
	sw	a5,4(sp)
	lw	a5,-40(s0)
	sw	a5,0(sp)
	lw	a7,-36(s0)
	lw	a6,-32(s0)
	lw	a5,-24(s0)
	lw	a4,-28(s0)
	call	cnn_layer
	li	a5,5
	sw	a5,-24(s0)
	li	a5,5
	sw	a5,-28(s0)
	li	a5,4
	sw	a5,-32(s0)
	li	a5,2
	sw	a5,-36(s0)
	li	a5,2
	sw	a5,-40(s0)
	sw	zero,-44(s0)
	sw	zero,-52(s0)
	li	a5,-4096
	addi	a5,a5,868
	addi	a4,s0,-16
	add	a1,a4,a5
	li	a5,-4096
	addi	a5,a5,368
	addi	a4,s0,-16
	add	a0,a4,a5
	lw	a7,-52(s0)
	lw	a6,-44(s0)
	lw	a5,-40(s0)
	lw	a4,-36(s0)
	lw	a3,-32(s0)
	lw	a2,-28(s0)
	call	cnn_pool
	addi	a4,s0,-204
	li	a5,-4096
	addi	a5,a5,868
	addi	a3,s0,-16
	add	a5,a3,a5
	mv	a3,a4
	li	a2,1
	li	a1,5
	mv	a0,a5
	call	cnn_to_fc
	li	a5,5
	sw	a5,-56(s0)
	li	a5,5
	sw	a5,-60(s0)
	sw	zero,-64(s0)
	addi	a5,s0,-204
	lw	a1,-56(s0)
	mv	a0,a5
	call	fc_input_generator
	addi	a4,s0,-184
	addi	a5,s0,-164
	lw	a3,-60(s0)
	lw	a2,-56(s0)
	mv	a1,a4
	mv	a0,a5
	call	fc_weight_generator
	addi	a3,s0,-224
	addi	a2,s0,-204
	addi	a1,s0,-184
	addi	a0,s0,-164
	lw	a6,-64(s0)
	lw	a5,-60(s0)
	lw	a4,-56(s0)
	call	fc_layer
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L115:
	lw	a4,-20(s0)
	li	a5,2
	ble	a4,a5,.L116
	li	a5,0
	mv	a0,a5
	addi	sp,sp,1728
	lw	ra,2028(sp)
	lw	s0,2024(sp)
	addi	sp,sp,2032
	jr	ra
	.size	main, .-main
	.ident	"GCC: (GNU) 9.2.0"
