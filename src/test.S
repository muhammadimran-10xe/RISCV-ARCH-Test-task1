#include "macro.S"
#define TRAP_FRAME  \
        .section .bss; \
        .align 6; .global trap_frame; trap_frame: .space 256;   
#define RVTEST_DATA_BEGIN                                               \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 6; .global tohost; tohost: .dword 0; .size tohost, 8;    \
        .align 6; .global fromhost; fromhost: .dword 0; .size fromhost, 8;\
        .popsection;                                                    \
        .align 4; .global begin_signature; begin_signature:
#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  6;                                                      \
        .global _start;                         
_start:                                 
    la sp, _sstack  /* initialized the stack */
    la t1, trap_vector       /* trap handler runs in M-mode/No delegation is used */
    csrw mtvec, t1           /* set mtvec to point to trap_vector */
    # la t0, trap_frame   
    # csrw mscratch , t0  /* this is not used instead macro.S */
                            /* uses mscratch to point to the trap frame and save/restore registers directly from/to mscratch */
    j main               /* jump to main test code */
trap_vector: 
    SAVE_REGS                  /* save all registers to the trap frame pointed to by mscratch */                                         
    csrr t0, mcause        /* read mcause to determine the cause of the trap */
    slli t0, t0, 1       
    srli t0, t0, 1        /* shift left and right to discard the MSB(interrupt) bit */
    li t1, 8             /* ECALL from U-mode mcause = 8 */
    li t2, 9             /* ECALL from S-mode mcause =  9 */
    beq t0, t1, u_trap_handler     /* if ECALL from U-mode, jump to handle_ecall_u */
    beq t0, t2, s_trap_handler     /* if ECALL from S-mode, jump to handle_ecall_s */
    j unknown_trap         /* if trap cause is unexpected, jump to unknown_trap */

main:
    .align 6
    la t3, begin_signature  /* load address of begin_signature to t3 */
    li t4, 0                 /* test counter = 0 */
    sw t4, 0(t3)             /* write test counter value to begin_signature */
    sw zero, 4(t3)          /* pass count in begin signature */
    sw zero, 8(t3)          /* fail count in begin signature */
    /* Test 1: Switch to S-mode and execute ECALL */
    li t4, 1                 /* set test counter = 1 */
    sw t4, 0(t3)             /* write test counter value to begin_signature */
    li a0, 0                 /* set argument a0 = 0 switch to S-mode/ a0 = 1 switch to U-mode */
    jal switch_mode          /* jump to switch_mode to switch to the desired mode and execute ECALL */
    lw t4, 4(t3)             /* load pass count */
    addi t4, t4, 1           /* increment pass count */
    sw t4, 4(t3)             /* write back pass count */
    ecall                     /* ecall in s-mode, should trap to M-mode and handled by s_trap_handler which will switch to S-mode and return to main */
    lw t4, 4(t3)             /* load pass count */
    addi t4, t4, 1           /* increment pass count */
    sw t4, 4(t3)             /* write back pass count */
    li a0, 1                 /* set argument a0 = 1 to switch to U-mode */
    jal switch_mode          /* jump to switch_mode to switch to U-mode and execute ECALL */
    lw t4, 4(t3)             /* load pass count */
    addi t4, t4, 1           /* increment pass count */
    sw t4, 4(t3)             /* write back pass count */
    ecall                    /*ecall in u-mode
    
    /* End of tests */
    j write_tohost            /* if execution continues after ECALL, write to tohost to indicate failure */
/* switch_mode: set MPP bits in mstatus and set mepc 
    to desired mode address and jumps to that mode using mret*/
switch_mode:
    mv t6, ra                  /* save return address in t6 */
    csrr t0, mstatus        /* read mstatus */
    li t1, 0x3              /* mask for MPP bits (bits 11 and 12) */
    slli t1, t1, 11         /* shift to correct position */
    not t1, t1
    and t0, t0, t1          /* clear MPP  */
    li t5, 1
    beq a0, zero, 1f        /* if a0 == 0, switch to S-mode, else switch to U-mode */
    beq a0, t5, 2f
    j unknown_trap             /* if a0 is not 0 or 1, jump to unknown_trap */


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
/* Trap handler for ECALL from U-mode
    This handler will set MPP to 01 to switch to S-mode and return using mret
    which will cause the processor to switch to S-mode and jump to the instruction after ECALL in main */
u_trap_handler:
    csrr t2, mepc        /* read mepc to get the address of the instruction that caused the trap */
    addi t2, t2, 4       /* increment mepc to point to the next instruction after ECALL */
    csrw mepc, t2
    csrr t0, mstatus    
    li t1, 3                /* mask = 0b11 */
    slli t1, t1, 11         /* shift to bits 11:12 */
    not t1, t1              /* invert to create clear mask */
    and t0, t0, t1          /* clear MPP bits */
    
    li t1, 1                /* MPP value = 01 */
    slli t1, t1, 11         /* shift to bits 11:12 */
    or t0, t0, t1           /* set MPP bits */
    csrw mstatus, t0
    RESTORE_REGS            /* restore the context */
    mret                   /* mret is used to return from trap and will switch to the mode specified in MPP */
/* Trap handler for ECALL from S-mode
    This handler will set MPP to 11 to switch to M-mode and return using mret
    which will cause the processor to switch to M-mode and jump to the instruction after ECALL in main */
s_trap_handler:
    csrr t2, mepc        /* read mepc to get the address of the instruction that caused the trap */
    addi t2, t2, 4       /* increment mepc to point to the next instruction after ECALL */
    csrw mepc, t2
    csrr t0, mstatus
    li t1, 3                /* mask = 0b11 */
    slli t1, t1, 11         /* shift to bits 11:12 */
    not t1, t1              /* invert to create clear mask */
    and t0, t0, t1          /* clear MPP bits */

    li t1, 3                /* MPP value = 11 */
    slli t1, t1, 11         /* shift to bits 11:12 */
    or t0, t0, t1           /* set MPP bits */
    csrw mstatus, t0
    RESTORE_REGS
    mret

unknown_trap:
    la t0, begin_signature
    lw t1, 8(t0)             /* load fail count */
    addi t1, t1, 1           /* increment fail count */
    sw t1, 8(t0)             /* write back fail count */

write_tohost:
    li gp, 1
    sw gp, tohost, t5
    j write_tohost

base:
.word 0xcafebeef
RVTEST_DATA_BEGIN
TRAP_FRAME
