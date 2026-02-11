#define RVTEST_DATA_BEGIN                                               \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 6; .global tohost; tohost: .dword 0; .size tohost, 8;    \
        .align 6; .global fromhost; fromhost: .dword 0; .size fromhost, 8;\
        .popsection;                                       
#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  6;                                                      \
        .global _start;  
RVTEST_CODE_BEGIN                         
_start:                                 
    # la sp, _sstack           /* initialized the stack */
    la t6, trap_vector       /* trap handler runs in M-mode/No delegation is used */
    csrw mtvec, t6           /* set mtvec to point to trap_vector */
    la t5, begin_signature     /* load address of signature region base to t5, trap handlers will use t5 to write test results */
    j main                   /* jump to main test code */
    
trap_vector:                               
    csrr t0, mcause            /* read mcause to determine the cause of the trap */
    slli t0, t0, 1       
    srli t0, t0, 1             /* shift left and right to discard the MSB(interrupt) bit */
    li t1, 8                   /* ECALL from U-mode mcause = 8 */
    li t2, 9                   /* ECALL from S-mode mcause =  9 */
    beq t0, t1, u_trap_handler     /* if ECALL from U-mode, jump to handle_ecall_u */
    beq t0, t2, s_trap_handler     /* if ECALL from S-mode, jump to handle_ecall_s */

    j fail             /* if trap cause is unexpected, jump to unknown_trap */

main:
    .align 6
    li a0, 0                   /* set argument a0 = 0 switch to S-mode/ a0 = 1 switch to U-mode */
    jal switch_mode            /* jump to switch_mode to switch to S-mode */
s_mode_code:
    j switch_to_u_mode         /* switch to U-mode */
u_mode_code:
    ecall                    /* ecall in u-mode return in s-mode*/
    ecall                    /* ecall in s-mode return in machine mode */
    j write_tohost            

switch_mode:
    mv t6, ra                  /* save return address in t6 */
    csrr t0, mstatus         
    li t1, 3                /* mask = 0b11 */
    slli t1, t1, 11         /* shift to bits 11:12 */
    not t1, t1              /* invert to create clear mask */
    and t0, t0, t1          /* clear MPP bits */
    li t3, 1                
    beq a0, zero, 1f           /* switch to S-mode */
    beq a0, t3, 2f             /* switch to U-mode */
    j fail                     /* if a0 is not 0 or 1, jump to unknown_trap */

/* this label write MPP bits to 01 to switch to S-mode
    set mepc to next instruction after switch_mode and return from trap */
1:
    li t1, 1
    slli t1, t1, 11
    or t0, t0, t1
    csrw mepc , t6
    csrw mstatus, t0
    mret
2:
    csrw mepc , t6
    csrw mstatus, t0
    mret
switch_to_u_mode:
    csrr t0, sstatus
    li t1, ~(1 << 8)
    and t0, t0, t1
    csrw sstatus, t0
    la t2, u_mode_code
    csrw sepc, t2
    sret
/* Trap handler for ECALL from U-mode
    This handler will set MPP to 01 to switch to S-mode and return using mret
    which will cause the processor to switch to S-mode and jump to the instruction after ECALL in main */
u_trap_handler:

    csrr    t2, mepc
    addi    t2, t2, 4          /* Skip the ECALL */
    csrw    mepc, t2
    csrr    t0, mstatus        /* Read mstatus */
    srli    t3, t0, 11
    andi    t3, t3, 3
    sb      t3, 2(t5)          /* Store previous privilege (MPP) */
    li      t1, ~(3 << 11)
    and     t0, t0, t1         /* Clear MPP bits */

    li      t1, (1 << 11)      /* Set MPP = 01 (S-mode) */
    or      t0, t0, t1
    csrw    mstatus, t0

    mret
/* Trap handler for ECALL from S-mode
    This handler will set MPP to 11 to switch to M-mode and return using mret
    which will cause the processor to switch to M-mode and jump to the instruction after ECALL in main */
s_trap_handler:

    csrr    t2, mepc          /* Skip the ECALL */
    addi    t2, t2, 4
    csrw    mepc, t2
    csrr    t0, mstatus       /* Read mstatus */
    srli    t3, t0, 11
    andi    t3, t3, 3
    sb      t3, 1(t5)         /* Store previous privilege (MPP) */

    li      t1, (3 << 11)
    or      t0, t0, t1      
    csrw    mstatus, t0       /* Set MPP = 3 (Machine) */

    mret

fail:
    la t1, base
    lw gp, 0(t1)
    la t0, tohost
    sw gp, 0(t0)              /* write to tohost 0xdeadbeef on failure*/
    j fail
  
write_tohost:
    li gp, 1
    la t0, tohost
    sw gp, 0(t0)              /* write to tohost 1 on success*/
    j write_tohost


RVTEST_DATA_BEGIN
.align 4; .global begin_signature; 
begin_signature:
    .fill 4, 1, 0  
end_signature:
base:
.word 0xcafebeef
