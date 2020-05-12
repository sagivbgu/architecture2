section .bss
    stack: resd 1 ; Address of the operand stack

section .data
    debug: db 0
    stackSize: db 5 ; Operand stack size (default: 5. Min: 2, Max: 0xFF)
    itemsInStack: db 0 ; Current items in stack (start value: 0)
    
; TODO: REMOVE THIS LINE    dashSign: equ 45 ; '-'

section .text                    	
    align 16
    global main
    extern printf
    extern fprintf
    extern fflush
    extern malloc
    extern calloc
    extern free
    extern gets
    extern getchar
    extern fgets

main:
    ; Process command line arguments (all optional): "-d" or stackSize
    mov ecx, [esp+4] ; ecx = argc
    mov ebx, [esp+8] ; ebx = argv

    ; Skip argv[0], it's just the file path
    add ebx, 4
    dec ecx
    jz callMyCalc ; Skip arguments parsing if there aren't any

    ; Search for relevant arguments
    parseArgument:
        mov edx, [ebx] ; edx = argv[i] (starting i = 1)
        mov edx, [edx] ; edx = argv[i][0]
        
        parseDebugMode:
            and edx, 0x00FFFFFF ; Now the first byte (= last char of a string) of edx is zeros
            cmp edx, 0x0000642D ; "-d\0\0" (The first \0 is due to the previous line)
            jne parseStackSize
            ; Now we know the only chars of argument are '-d'
            mov byte [debug], 1 ; debug = 1
            jmp endParseArgument

        parseStackSize:
            and edx, 0x0000FFFF ; Now the first 2 bytes (= last 2 chars of a string) of edx are zeros
            
            ;
            ; TODO: Convert string to number
            ;

        endParseArgument:
            add ebx, 4
            loop parseArgument, ecx ; Decrement ecx and if ecx != 0, jump to the label

    ; Call the primary loop
    callMyCalc:
        push dword 0 ; so that [ebp-4] = operations performed (start value: 0. Max: 2^31)
        call myCalc
        
    ; Print number of operations performed
    ; Assuming operations performed is still on the stack
    push dword 0x00006425; "%d\0\0"
    call printf

    finishProgram:
        add esp, 8
        mov eax, 0
        ret

myCalc:
    ; TODO