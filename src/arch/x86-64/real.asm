; real mode assembly

extern start32

; get the size of the kernel
extern KERNEL_SECTORS

section .bootloader
; we're only 16 bits right now
[bits 16]
    start:
        ; there is free memory below us, we can use that for the stack
        mov sp, 0x7C00

        xor ax, ax
        mov ds, ax
        mov es, ax
        mov ss, ax
        mov fs, ax
        mov gs, ax

        cld

        mov ax, 2
        int 0x10 ; clear screen

        mov ah, 0 ; clear disk status
        int 0x13 ; int 0x13, ah = 0

        ; read in the rest of the code from disk and put it in the sectors afterwards
        mov bx, 0x7E00 ; read it in after this memory 
        mov al, KERNEL_SECTORS ; we need this many sectors 
        ; TODO: at the point we have more than 1440 sectors this will break
        mov ch, 0 ; from the first cylinder
        mov dh, 0 ; and the first head
        mov cl, 2 ; the second sector (we are in the first sector already)
        mov ah, 2 ; ah = 2 means read from disk
        int 0x13 ; disk interrupt

        ; prepare to go to protected mode

        ; enable the a20 line

        mov ax, 0x2403 ; does this cpu support the a20 gate?
        int 0x15
        jb .a20_no ; no support
        cmp ah, 0
        jb .a20_no ; no support

        mov ax, 0x2402 ; what is the status of the a20 gate?
        int 0x15
        jb .a20_fail ; failed to get status
        cmp ah, 0
        jnz .a20_fail ; failed to get status

        cmp al, 1
        jz .a20_on ; the a20 gate is already activated

        mov ax, 0x2041 ; lets try to activate the a20 gate
        int 0x15
        jb .a20_fail ; failed to activate the gate
        cmp ah, 0
        jnz .a20_fail ; failed to activate the gate

    .a20_on: ; the a20 works
        
        ; lets do E820 memory mapping

        mov ebx, 0 ; continuation 

        mov edi, [memory_base] ; memory map pointer
        jmp .begin_mapping

    .next_map:
        add edi, ecx
    .begin_mapping:

        ; these two registers are trashed by the call
        mov eax, 0xE820 ; function code
        mov edx, 0x534D4150 ; signature (SMAP)
        mov ecx, 24 ; memory map size

        int 0x15 ; memory interrupt

        cmp ebx, 0 ; is there another map segment?
        jne .next_map

        ; set the memory map pointer to the end of mapped memory
        mov [memory_base], edi

        cli ; we wont be needing interrupts for now

        ; load the global descriptor table
        lgdt [descriptor]

        ; go to protected mode
        mov eax, cr0
        or eax, 1 ; set the protected mode bit
        mov cr0, eax

        push (descriptor.data - descriptor)
        ; jump to 32 bit code
        jmp (descriptor.code - descriptor):start32

    .a20_fail: ; failed to activate the a20 gate
        mov si, fail_a20
        jmp real_panic
    .a20_no: ; the a20 gate isnt supported
        mov si, no_a20
        ; fallthrough to real_panic

    ; panic in real mode
    ; never returns
    ; set si = message
    real_panic:
        cld
        mov ah, 0x0E
    .put:
        lodsb ; put next character in al
        or al, al ; is character null
        jz .end ; if it is then halt
        int 0x10 ; write char intterupt
        jmp .put ; write again
    .end:
        cli
        hlt
        jmp .end

    fail_a20 db "a20 line failed", 0
    no_a20 db "a20 line not supported", 0

    descriptor:
        .null:
            dw descriptor.end - descriptor - 1
            dd descriptor
            dw 0
        .code:
            dw 0xFFFF
            dw 0
            db 0
            db 10011010b
            db 11001111b
            db 0
        .data:
            dw 0xFFFF
            dw 0
            db 0
            db 10010010b
            db 11001111b
            db 0
        .end:

    ; 0x500 - 0x7BFF is used for the stack so lets not touch that area
    ; 0x7E00 - 0x7FFF on the other hand is usable so lets use that
    global memory_base ; this is going to be used in other places as well so make it global
    memory_base: dd 0x7E00

    ; pad the rest of the file with 0x0 up to 510
    times 510-($-$$) db 0
    db 0x55 ; file[511] = 0x55
    db 0xAA ; file[512] = 0xAA
    ; boot magic number to mark this as a valid bootsector