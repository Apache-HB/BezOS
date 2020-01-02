; number of 512 byte sectors the kernel takes up
extern KERNEL_SECTORS

; size of the kernel aligned to page
extern KERNEL_END

; 32 bit protected mode code
extern start32

section .boot
bits 16
    start:
        ; we need to load in the next sectors after the kernel
        ; we do this by passing alot of data into registers
        ; we set
        ; bx = memory to start loading disk data into
        ; al = number of 512 byte sectors to load
        ; ch = the cylinder to read from
        ; dh = the head to read from
        ; cl = the first sector we want to read from
        ; ah = 2 which is the number chosen to read from disk
        ;
        ; then once we setup all the registers we 
        ; call the disk interrupt to execute our disk query

        mov bx, [low_memory] ; we need to load them into the sectors after the boot sector
        mov al, KERNEL_SECTORS ; we need all the sectors
        ; TODO: account for KERNEL_SECTORS > 1440
        mov ch, 0 ; take them from the first cylinder
        mov dh, 0 ; and the first head
        mov cl, 2 ; we start reading from the second sector because the first was already loaded
        mov ah, 2 ; and ah = 2 means we want to read in so we dont overwrite the disk 
        int 0x13 ; then we do the disk interrupt to perform the action

        ; we have used this so mark it as used
        add dword [low_memory], KERNEL_END

        ; next we need to enable the a20 line
        ; we do this by checking
        ; 1. does the current cpu even have the a20 gate?
        ; 2. is the a20 gate already enabled?
        ; 3. if not, try to enable it
        ;
        ; if any of these steps fail we will just error and not boot

        ; step 1. check if the cpu has an a20 gate
        mov ax, 0x2403 ; ax = 0x2403 means we are querying for the existence of the gate
        int 0x15 ; this executes our query
        jb .a20_no ; if the query fails then we obviously dont have the gate
        ;            or the cpu is buggy, but probably the former

        ; ah stores the output of the query
        ; we now need to check if eh is 0
        ; if it is we dont have an a20 gate
        ; this means we are running on a very old chip that only supports real mode
        cmp ah, 0 
        jb .a20_no

        ; step 2. check if the a20 gate is already enabled
        ; if it is then we dont need to enable it again
        mov ax, 0x2402 ; ax = 0x2402 means we are querying for the status of the gate
        int 0x15 ; now we execute the query
        jb .a20_failed ; if the query failed then something is wrong with the chip

        ; now we check ah for the output to see if the gate is already enabled
        cmp ah, 0 ; if ah != zero then something is wrong with the a20 gate
        jnz .a20_failed

        ; if al == 1 that means that the gate is already active
        ; some bios's have an option to enable this as do some emulators
        cmp al, 1
        jz .a20_enabled ; so  if it is enabled we can skip enabling it again in the next step

        ; now for the final step we try and enable the a20 line if it isnt already
        mov ax, 0x2401 ; ax = 0x2401 is the code to try and enable the gate
        int 0x15 ; tell the chip to enable the gate
        jb .a20_failed ; if the call failed then the chip is either faulty or 30 years old

        ; ah == 0 if the gate was enabled
        cmp ah, 0
        jnz .a20_failed ; if the gate wasnt zero then something went wrong

    .a20_enabled:
        ; if we get here that means that the a20 gate was successfully enabled

        ; next we have to do the whole memory mapping thing so that later code
        ; knows where we can and cant put stuff
        ; overwriting the bios isnt something we want to do really

        ; so lets begin memory mapping
        ; the bios has an interrupt for this and a function code (0xE820)
        ; this returns a small struct with all the bits we need for our first memory map
        ; we can always read more complicated data in later but for now we dont need it
        ; and if its good enough for linux its probably good enough for us

        ; continuation byte
        mov ebx, 0

        ; output location
        mov edi, [low_memory]

    .next_map:
        add edi, ecx
    .begin_map:
        
        mov eax, 0xE820 ; E820 function code
        mov edx, 0x534D4150 ; signature (SMAP)
        mov edi, 24 ; desired output size (it may return 20 bytes if it doesnt support acpi3 attributes)

        int 0x15 ; memory map interrupt

        ; continuation is put into ebx, if its not 0 there are more sections to read
        cmp ebx, 0
        jne .next_map

    .end_map:

        mov [low_memory], edi

        cli ; clear interrupts

        ; enable protected mode bit
        mov eax, cr0 
        or eax, 1
        mov cr0, eax

        ; load the global descriptor table
        lgdt [descriptor]
        
        push (descriptor.data - descriptor)
        jmp (descriptor.code - descriptor):start32

        ; this means that some step of the enabling code failed
    .a20_failed:

        ; if we are here then the a20 line doesnt exist
        ; welcome to the 1970s
    .a20_no:
    

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

    
    ; pointer to the 480KB above the kernel
    global low_memory
    low_memory: dd 0x7E00

    ; byte 511, 512 of the first sector need to have this magic
    ; to mark this as a bootable sector
    times 510 - ($-$$) db 0
    dw 0xAA55