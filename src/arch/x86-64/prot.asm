extern start64

extern LOW_MEMORY

%define VGA_WIDTH 80
%define VGA_HEIGHT 25

section .protected
bits 32
    global start32
    start32:
        ; when we get here the bootloader has set 
        ; ax = data segment

        ; so now we set the segments
        mov ds, ax
        mov ss, ax

        ; clear general segments
        xor ax, ax

        mov gs, ax
        mov fs, ax
        mov es, ax

        call vga_init

    enable_cpuid:
        ; check if we have cpuid by checking eflags
        pushfd
        pop eax

        mov ecx, eax

        xor eax, 1 << 21

        push eax
        popfd

        pushfd
        pop eax

        push ecx
        popfd

        xor eax, ecx
        jz cpuid_fail

        ; if we have cpuid we need extended cpuid
        mov eax, 0x80000000
        cpuid
        cmp eax, 0x80000001
        jb cpuid_fail

        ; now we use cpuid to check for long mode
        mov eax, 0x80000001
        cpuid 
        test edx, 1 << 29
        jz long_fail

    enable_features:
        ; enable some cpu features for later use
        ; first enable the fpu because floats seem useful
        mov eax, cr0
        and eax, (-1) - ((1 << 2) | (1 << 3))
        mov cr0, eax

        fninit
        fnstsw [fpu_data]
        cmp word [fpu_data], 0
        jne fpu_fail ; if the fpu fails to store data then we dont have an fpu unit

        ; next enable sse and sse2
        mov eax, 1
        cpuid
        test edx, 1 << 25
        jz sse_fail

        mov eax, cr0
        ; disable emulation
        and eax, ~(1 << 2)
        ; enable coproccessor
        or eax, 1
        mov cr0, eax

        ; enable fpu save/restore functions and sse exceptions
        mov eax, cr4
        or eax, (1 << 9) | (1 << 10)
        mov cr4, eax

        ; time to enable paging
        call paging_init

        ; move the top page table to cr3
        mov cr3, eax

        ; time to enable PAE for 64 bit addresses in the page table
        ; this is also required for long mode

        mov eax, cr4
        or eax, (1 << 5) | (1 << 4)
        mov cr4, eax

        ; enable long mode
        mov ecx, 0xC0000080
        rdmsr
        or eax, 1 << 8
        wrmsr

        ; enable paging and WP flag for read only memory support
        mov eax, cr0
        or eax, 1 << 31
        mov cr0, eax

        ; load the 64 bit gdt to enable full 64 bit mode
        lgdt [low_gdt]

        mov ax, descriptor64.data

        ; then long jump to main
        jmp descriptor64.code:start64

    cpuid_fail:
        push cpuid_msg
        jmp panic

    long_fail:
        push long_msg
        jmp panic

    fpu_fail:
        push fpu_msg
        jmp panic

    sse_fail:
        push sse_msg
        jmp panic

    panic:
        call vga_print
    .end:
        cli
        hlt
        jmp .end

    ; bonks eax
    ; clears the vga text screen
    vga_init:
        ; counter register
        mov eax, 0
    .next:
        ; if(eax == VGA_WIDTH * VGA_HEIGHT)
        ;     return
        cmp eax, VGA_HEIGHT * VGA_WIDTH
        je .end

        ; (word*)0xB8000[eax] = ' ' | 7 << 8
        mov word [0xB8000+eax], 32 << 8
        ; eax++
        inc eax
        jmp .next
    .end:
        ret

    ; edx = string to print
    ; bonks ebx, ecx, al
    ; prints to vga output
    vga_print:
    .next:
        ; ebx = char to print
        mov ebx, [edx]

        ; if ebx is zero then return
        cmp ebx, 0
        je .end

        ; if ebx is a newline then go to the next line
        cmp ebx, 10
        jne .no_update_newline
    
        mov byte [vga_column], 0
        inc byte [vga_row]

    .no_update_newline:

        cmp byte [vga_column], VGA_WIDTH
        jng .no_update_column

        mov byte [vga_column], 0
        inc byte [vga_row]

    .no_update_column:

        cmp byte [vga_row], VGA_HEIGHT
        jng .no_update_row

        mov byte [vga_row], 0

    .no_update_row:

        mov al, byte [vga_row]
        imul eax, eax, VGA_WIDTH
        add al, byte [vga_column]

        ; encode colour into char
        or bx, 7 << 8

        mov word [0xB8000+eax], bx

        inc byte [vga_column]

        inc edx

        jmp .next
    .end:
        ret

    paging_init:
        mov word [0xB8000], 69 | 7 << 8
        mov edx, sse_msg
        call vga_print

        ; page align low memory ptr
        mov eax, [LOW_MEMORY]
        add eax, 0x1000 - 1
        and eax, -0x1000

        ; eax = pml4
        ; ebx = pml3
        mov ebx, eax
        sub ebx, 0x1000

        ; ecx = pml2
        mov ecx, ebx
        sub ecx, 0x1000

        ; edx = pt
        mov edx, ecx
        sub edx, 0x1000

        ; pml4[0] = pml3 | 3
        mov esi, ebx
        or esi, 3
        mov [eax], esi

        ; pml3[0] = pml2 | 3
        mov esi, ecx
        or esi, 3
        mov [ebx], esi

        ; pml2[0] = pt | 3
        mov esi, edx
        or esi, 3
        mov [ecx], esi

        ; eax = 0
        ; loop counter
        xor eax, eax

    .fill_table:

        mov edi, eax
        imul edi, edi, 0x1000
        or edi, 3

        ; pt[i] = (i * 0x1000) | 3
        mov [edx+eax], edi

        ; if rsi != 512 goto fill_table
        cmp eax, 512
        jne .fill_table

        ret

    vga_row: db 0
    vga_column: db 0

    cpuid_msg: db "cpuid not detected", 0
    long_msg: db "cpu is 32 bit, 64 bit is required", 0
    fpu_msg: db "fpu unit is not detected", 0
    sse_msg: db "sse is not detected", 0

    fpu_data: dw 0xFFFF

    global high_gdt

    align 16
    low_gdt:
        dw descriptor64.end - descriptor64 - 1
        dd descriptor64

    align 16
    high_gdt:
        dw descriptor64.end - descriptor64 - 1
        dq descriptor64

    align 16
    descriptor64:
        .null:
            dw 0
            dw 0
            db 0
            db 0
            db 0
            db 0
        .code: equ $ - descriptor64
            dw 0
            dw 0
            db 0
            db 10011010b
            db 00100000b
            db 0
        .data: equ $ - descriptor64
            dw 0
            dw 0
            db 0
            db 10010010b
            db 00000000b
            db 0
        .end:

%if 0
        ; page align eax
        mov eax, [LOW_MEMORY]
        add eax, 0x1000 - 1
        and eax, -0x1000

        ; push pml4 rbp-12
        push eax
        add eax, 0x1000

        ; push pml3 rbp-8
        push eax
        add eax, 0x1000

        ; push pml2 rbp-4
        push eax
        add eax, 0x1000

        ; push pt rbp
        push eax
        add eax, 0x1000


        ; pml4[0] = pml3 | 3
        mov eax, dword [rbp - 12]
        mov ebx, dword [rbp - 8]
        
        or ebx, 3
        mov [eax], ebx

        ; pml3[0] = pml2 | 3;
        mov eax, [rbp-8]
        mov ebx, [rbp-4]

        or ebx, 3
        mov [eax], ebx

        ; pml2[0] = pt | 3;
        mov eax, [rbp-4]
        mov ebx, [rbp]

        or ebx, 3
        mov [eax], ebx

        mov eax, [rbp] ; eax = pt

        ; counter
        mov ebx, 0
    .fill_table:
        cmp 512, ebx
        ja .end

        mov ecx, ebx
        imul ecx, ecx, 0x1000
        or ecx, 3

        mov [eax+ebx], ecx

        jmp .fill_table

%endif