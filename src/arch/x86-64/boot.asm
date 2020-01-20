global start16

extern start32

bits 16
section .boot
    start16:

    enable_a20:
        call a20check
    
    .bios:
        mov ax, 0x2401
        int 0x15

        call a20check

    .kbd:
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
        out 0x64, al

        call a20wait
        mov al, 0xAE
        out 0x64, al

        call a20wait

        sti

        call a20check
    
    .port:
        in al, 0xEE
        call a20check

    .fail:
        mov si, a20_msg
        jmp panic

        ; collect e820 bios memory map
        ; this can only be done in real mode so do it now
        ; the less mode switching later on the better

        ; next we have to do the whole memory mapping thing so that later code
        ; knows where we can and cant put stuff
        ; overwriting the bios isnt something we want to do really

        ; so lets begin memory mapping
        ; the bios has an interrupt for this and a function code (0xE820)
        ; this returns a small struct with all the bits we need for our first memory map
        ; we can always read more complicated data in later but for now we dont need it
        ; and if its good enough for linux its probably good enough for us

        ; we want to layout the tables like so
        ;
        ; [entry1(20/24) | u32 size]
        ; [entry2(20/24) | u32 size]
        ; [entryN(20/24) | u32 size]
        ;
        ; this means we can read in 4 bytes from the top of our "stack" of tables
        ; then using those 4 bytes we know how much to read afterwards
        ; we store the size for each entry because im not sure if
        ; the standards define whether sizes can be mixed or not
        ; so better safe than sorry

    collect_e820:
        mov ebx, 0
        mov edi, [LOW_MEMORY]

        mov dword [edi], 0
        add edi, 4

        jmp .begin
    .next:
        add edi, ecx
        mov dword [edi], ecx
        add edi, 4
    .begin:
        mov eax, 0xE820
        mov edx, 0x534D4150
        mov ecx, 24

        int 0x15

        cmp ecx, 20
        je .fix_size

        cmp ecx, 24
        jne .fail
    .fix_size:
        cmp eax, 0x534D4150
        jne .fail

        cmp ebx, 0
        jne .next
    .end:
        mov [LOW_MEMORY], edi
        jmp enter_prot
    .fail:
        ; if the e820 mapping fails then panic
        mov si, e820_msg
        jmp panic

    enter_prot:
        cli

        ; load the global descriptor table
        lgdt [descriptor]

        ; enable the protected mode bit
        mov eax, cr0
        or eax, 1
        mov cr0, eax

        ; set ax to the data descriptor
        mov ax, (descriptor.data - descriptor)

        ; jump into protected mode code
        jmp (descriptor.code - descriptor):start32

    a20wait:
        in al, 0x64
        test al, 2
        jnz a20wait
        ret

    a20wait2:
        in al, 0x64
        test al, 1
        jz a20wait2
        ret

    ; check if the a20 line is enabled by using the memory wrap around
    a20check:
        mov ax, word [es:0x7DFE] ; 0x0000:0x7DFE is the same address as 0xFFFF:0x7E0E due to wrap around
        cmp word [fs:0x7E0E], ax ; this is the boot signature, we compare these to see if the wraparound is disabled
        je .change

    .change:
        mov word [es:0x7DFE], 0x6969 ; change the values to make sure the memory wraps around
        cmp word [fs:0x7E0E], 0x6969
        jne collect_e820
    .end:
        mov word [es:0x7DFE], ax ; write the boot signature back for next time
        ret

    panic:
        cld
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

    global LOW_MEMORY
    LOW_MEMORY: dd 0x7C00

    a20_msg: db "failed to enable a20 line", 0
    e820_msg: db "failed to collect e820 memory map", 0

    descriptor:
        .null:
            dw descriptor.end - descriptor - 1
            dd descriptor
            dw 0
        .code:
            dw 0xFFFF
            dw 0
            db 0
            db 0x9A
            db 11001111b
            db 0
        .data:
            dw 0xFFFF
            dw 0
            db 0
            db 0x92
            db 11001111b
            db 0
        .end: