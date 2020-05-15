section .bss
    stack: resd 1 ; Address of the operand stack
    buffer: resb 81 ; The input buffer - 81 bc \n is also saved 

section .rodata
    printNumberFormat: db "%d", 10, 0
    calcMsg: db "calc: ",0
    printStringFormat: db "%s", 10, 0	; format string

section .data
    debug: db 0
    stackSize: db 5 ; Operand stack size (default: 5. Min: 2, Max: 0xFF)
    itemsInStack: db 0 ; Current items in stack (start value: 0)

section .text                    	
    align 16
    global main
    extern printf
    extern fprintf 
    extern fflush
    extern malloc 
    extern calloc 
    extern free 
    extern getchar 
    extern fgets 
 

%macro print 2 
    pushad
    mov ebx, 1
    mov ecx, %1
    mov edx, %2
    mov eax, 4
    int 0x80
    popad
%endmacro


%macro pushReturn 0; bc we have return value in eax we want to backup all the registers except eax
    push edx
    push ecx
    push ebx
    push esi
    push edi
%endmacro
%macro popReturn 0
    pop edx
    pop ecx
    pop ebx
    pop esi
    pop edi
%endmacro

%macro freeStack 0 ; we free the nodes from last to first - but its not really matter
    pushad
    mov ebx, stack
    freeLoop:
        cmp ebx, 0 ;comparing with null - if its equal we let them go (finally)
        je endFreeLoop
        mov eax, ebx
        add eax, 4 ;points to the next node
        freeNum ebx
        mov ebx, eax ;now ebx points to the next node
    endFreeLoop:
    popad
%endmacro

%macro freeNum 1 ; gets address
%endmacro

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
            pushad
            push dx
            call hexStringToByte
            mov [stackSize], al
            add esp, 2 ; "Remove" pushed dx from stack
            popad

        endParseArgument:
            add ebx, 4
            loop parseArgument, ecx ; Decrement ecx and if ecx != 0, jump to the label

    ; Call the primary loop
    callMyCalc: call myCalc
    freeStack
    ; Print number of operations performed
    ; Assuming operations performed is in eax
    push eax
    push printNumberFormat
    call printf

    finishProgram:
        add esp, 8
        mov eax, 0 ; Program exit code
        ret

myCalc:
    pushReturn
    mov eax, 4 
    push eax
    mov eax, [stackSize] ; stack size - we need to check somewhere else if the itemsOnStack is valid
    push eax   
    call calloc        
    popReturn ;keeps eax with the ret value
    add esp, 8 ;cleaning the stack from locals
    mov dword[stack], eax ; eax has the pointer to the start of the stack

    calcLoop:
        print calcMsg, 6
        pushReturn
        mov eax, 3 ; lines 82-86 reads the input to the buffer - eax has the number of bytes that have been recived - the input is valid no need to check
        mov ebx, 0
        mov ecx, buffer
        mov edx, 81
        int 0x80 
        popReturn
        dec eax ; lenght of the char without the \n

        cmp byte [buffer], 'q'
        je endCalcLoop
        cmp byte [buffer], '+'
        ;je 
        cmp byte [buffer], 'p'
        ;je 
        cmp byte [buffer], 'd'
        ;je 
        cmp byte [buffer], '&'
        ;je 
        cmp byte [buffer], '|'
        ;je 
        cmp byte [buffer], 'n'
        ;je 
        cmp byte [buffer], '*'
        ;je 
        ;its a number so we need to parse it
        ;add to the stack
        jmp calcLoop

    endCalcLoop:
        mov eax, [itemsInStack]
        ret


; Get a word representing 2 hexadecimal digits and return the value they represent.
; Result stored in al.
hexStringToByte:
    mov ebp, esp

    mov dx, [ebp+4]
    push dx
    call hexCharToValue
    ; al contains the value of the first letter

    shr dx, 8 ; So that dl = dh, dh = 0
    cmp dl, 0 ; If it's a null byte, ignore it
    jz returnStringValue ; al already contains the desired value

    shl al, 4 ; Multiply value by 0x10
    mov cl, al
    push dx
    call hexCharToValue

    add al, cl

    returnStringValue:
        mov esp, ebp
        ret

; Get a byte representing a hexadecimal digit and return the value it represents.
; Result stored in al.
hexCharToValue:
    mov al, [esp+4]
    sub al, 0x30
    cmp al, 9 ; Check if it's a char between '0' and '9'
    jle returnCharValue
    ; Now we know it's a char between 'A' and 'F'
    sub al, 0x7 ; Correct according to offset in ascii table
    returnCharValue: ret



