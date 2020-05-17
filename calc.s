section .bss
    stack: resd 1 ; Address of the operand stack
    buffer: resb 81 ; The input buffer - 81 bc \n is also saved 

section .rodata
    printNumberFormat: db "%d", 10, 0
    printStringFormat: db "%s", 10, 0	; format string

    calcMsg: db "calc: ", 0
    overflowMsg: db "Error: Operand Stack Overflow"
    
    NODEVALUE: equ 0 ; Offset of the value byte from the beginning of a node
    NEXTNODE: equ 1 ; Offset of the next-node field (4 bytes) from the beginning of a node

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

; Call a function WHICH DOESN'T EXPECT ANY PARAMETERS, automatically backing up all registers except eax
%macro callReturn 1
    pushReturn
    call %1
    popReturn
%endmacro

; bc we have return value in eax we want to backup all the registers except eax
%macro pushReturn 0
    push edx
    push ecx
    push ebx
    push esi
    push edi
    push ebp
%endmacro

%macro popReturn 0
    pop ebp
    pop edi
    pop esi
    pop ebx
    pop ecx
    pop edx
%endmacro

; we free the nodes from last to first - but its not really matter
%macro freeStack 0
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

%macro freeNode 1
push dword %1
call free
add esp, 4
%endmacro

; Convert the word %1 containing a hex digit string representation to its value
; and move it to %2.
%macro pushValue 2
push eax
pushReturn
push word %1
call hexStringToByte
add esp, 2 ; "Remove" pushed word from stack
popReturn
mov %2, al
pop eax
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
            pushValue dx, [stackSize]
            
        endParseArgument:
            add ebx, 4
            loop parseArgument, ecx ; Decrement ecx and if ecx != 0, jump to the label

    ; Call the primary loop
    callMyCalc: call myCalc
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
    mov eax, 4 
    push eax
    mov eax, [stackSize] ; stack size - we need to check somewhere else if the itemsInStack is valid
    push eax   
    call calloc        
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
        call pushHexStringNumber
        ;add to the stack
        jmp calcLoop

    endCalcLoop:
        freeStack
        mov eax, [itemsInStack] ; TODO: we need to return the number of operations performed, not current items in stack
        ret

; Get the number of bytes to read from the buffer, assuming it's a string representing a hex number.
; Convert the string to its numeric value and push it to the operand stack.
pushHexStringNumber:
    mov ebp, esp
    sub esp, 4 ; Will contain address of the first node
    
    ; Push the first node to the operand stack (and validate it's not full)
    callReturn createNode
    mov [ebp-4], eax ; Address of the new node

    callReturn pushNodeToOperandStack
    
    cmp eax, 0 ; Pushing succeeded
    jz pushHexStringNumberStart
    
    freeNode [ebp-4]
    jmp pushHexStringNumberEnd

    pushHexStringNumberStart:
    callReturn countLeadingZeros ; now eax = number of leading zeros
    
    convertBufferToNodes:
    mov ecx, [ebp+4] ; String length
    mov ebx, buffer
    add ebx, ecx
    dec ebx ; ebx = Address of last char
    sub ecx, eax ; ecx = string length - leading zeros.
                 ; This is the number of remaining chars to read
    mov edx, [ebp-4] ; edx = address of current node

    convertBufferLoop:
        ; If only 1 char needs to be read
        cmp ecx, 1
        mov ebx, [ebx - 1]
        shl ebx, 8 ; Pad with '\0'
        pushValue bx, [edx + NODEVALUE]
        jmp pushHexStringNumberEnd

        ; Else, read 2 chars
        pushValue [ebx - 1], [edx + NODEVALUE]

        ; If there are no more chars to read, jump end of function
        sub ebx, 2
        sub ecx, 2
        cmp ecx, 0
        jz pushHexStringNumberEnd

        callReturn createNode
        
        mov [edx + NEXTNODE], eax ; Set 'next' field of the previous node to point to the new one
        mov edx, eax
        jmp convertBufferLoop

    pushHexStringNumberEnd:
        mov esp, ebp
        ret
        
; Returns the number of leading '0' characters in buffer
countLeadingZeros:
    mov ebx, buffer
    mov eax, 0 ; Leading zeros counter
    countLeadingZerosLoop:
        cmp byte [ebx + eax], 0x30 ; '0' in ascii
        jne endCountLeadingZeros
        inc eax
        jmp countLeadingZerosLoop
    endCountLeadingZeros:
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

; Allocate memory for a node and put its address in eax.
createNode:
    push dword 1 ;size
    push dword 5 ;nmemb
    call calloc
    ; Address to the allocated memory is stored in eax
    add esp, 8
    ret

; Get an address of the starting node of the list and free the memory allocated for all of the nodes.
freeLinkedList:
    mov eax, [esp+4]

    freeNextNode:
    mov ebx, [eax + NEXTNODE]
    freeNode eax
    mov eax, ebx
    cmp eax, 0
    jnz freeNextNode
    ret


; Get an address of a node and push it to the end of operand stack.
; Returns 0 in eax in case of success, and 1 in case of failure.
pushNodeToOperandStack:
    ; Check if stack is full
    mov eax, [itemsInStack]
    cmp [stackSize], eax
    jne unsafePushNode
    push overflowMsg
    call printf
    mov eax, 1
    ret

    ; Push to the stack
    unsafePushNode:
    mov ebx, [esp+4]
    mov eax, [itemsInStack]
    mov [stack + 4 * eax], ebx
    inc byte [itemsInStack]
    mov eax, 0
    ret
