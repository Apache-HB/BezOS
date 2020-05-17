extern SECTORS


bits 16
section .boot16
prelude:
    cli
    cld
    jmp 0:start16
start16:
    xor ax, ax

    ; zero the data segment to make addressing easy
    mov ds, ax

    ; zero the stack segment and load the stack before the bootloader
    mov ss, ax
    mov sp, 0x7C00

    ; here the fs is set to 0xFFFF and es is set to 0
    ; this lets us test a20 wraparound later in the bootloader
    ; this is because [0xFFFF:0] and [0:0] point to the same address
    ; when wraparound is enabled
    mov es, ax
    not ax
    mov fs, ax

    ; make sure the disk extensions are supported
    mov ah, 0x41
    mov bx, 0x55AA
    int 0x13
    cmp bx, 0xAA55

    ; if the extensions arent supported then fail
    jnz fail_ext
    jc fail_ext

    ; load the number of required sectors
    mov word [dap.offset], SECTORS
    mov word [dap.segment], ds

    ; read from the disk
    mov ah, 0x42
    mov si, dap
    int 0x13

    jc fail_disk

    ; time to enable the a20 line

    ; if its already enabled then just skip it all
    call a20check

    ; try the bios call
    mov ax, 0x2401
    int 0x15
    call a20check

    ; now try the keyboard method

    cli

    call a20wait
    mov al, 0xAD
    out 0x64, al

    call a20wait
    mov al, 0xD0
    out 0x64, al

    call a20wait2
    in al, 0x60
    push eax

    call a20wait
    mov al, 0xD1
    out 0x64, al

    call a20wait
    pop eax
    or al, 2
    out 0x60, al

    call a20wait
    mov al, 0xAE
    out 0x64, al

    call a20wait
    sti

    ; check again
    call a20check

    ; here we try the fast a20 method
    in al, 0x92
    or al, 2
    out 0x92, al
    call a20check

    ; if none of these methods work then fail
    jmp fail_a20

    ; time to load the gdt for protected mode
load_gdt:
    lgdt [table]
    cli

    mov eax, cr0
    or al, 1
    mov cr0, eax

    ; jump to protected mode code
    jmp 0x18:start32

a20wait:
    in al, 0x64
    test al, 2
    jnz a20wait
    ret

a20wait2:
    in al, 0x64
    test al, 2
    jz a20wait2
    ret

a20check:
    ; compare the bootmagic using wraparound
    mov word [es:0x7DFE], 0x6969
    cmp word [fs:0x7E0E], 0x6969

    ; if there is no wraparound then the a20 line is enabled
    jne load_gdt
    ret

fail_ext:
    mov si, .msg
    jmp panic
    .msg: db "no extension", 0

fail_disk:
    mov si, .msg
    jmp panic
    .msg: db "bad disk", 0

fail_a20:
    mov si, .msg
    jmp panic
    .msg: db "bad a20", 0

panic:
    mov ah, 0x0E
.put:
    lodsb
    or al, al
    jz .end
    int 0x10
    jmp .put
.end:
    cli
    hlt
    jmp .end


table:
    dw .end - .start - 1
    dd .start
.start:

.null:
    dw 0 ; limit
    dw 0 ; base
    db 0 ; base
    db 0 ; access
    db 0 ; granularity
    db 0 ; base

; code 16
    dw 0xFFFF
    dw 0
    db 0
    db 10011010b
    db 0
    db 0

; data 16
    dw 0xFFFF
    dw 0
    db 0
    db 10010010b
    db 0
    db 0

; code 32
    dw 0xFFFF
    dw 0
    db 0
    db 10011010b
    db 11001111b
    db 0

; data 32
    dw 0xFFFF
    dw 0
    db 0
    db 10010010b
    db 11001111b
    db 0

; code 64
    dw 0
    dw 0
    db 0
    db 10011010b
    db 00100000b
    db 0

; data 64
    dw 0
    dw 0
    db 0
    db 10010010b
    db 0
    db 0
.end:

dap:
    .size: db 0x10 ; size of the packet
    .zero: db 0 ; always zero
    .sectors: dw 0 ; number of sectors to read
    .offset: dw 0
    .segment: dw 0
    .start: dq 1 

    times 510 - ($-$$) db 0
bootmagic:
    dw 0xAA55
bootend:


bits 32
section .boot32
start32:
    jmp $


bits 64
section .boot64
start64:
    jmp $