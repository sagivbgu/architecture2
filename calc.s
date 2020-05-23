section .bss
    stack: resd 1 ; Address of the operand stack
    buffer: resb 81 ; The input buffer - 81 bc \n is also saved 

section .rodata
    printNumberFormat: db "%d", 10, 0
    printStringFormat: db "%s", 10, 0	; format string

    calcMsg: db "calc: ", 0
    overflowMsg: db "Error: Operand Stack Overflow"
    illegalPop: db "Error: Insufficient Number of Arguments on Stack", 0
    
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
        je duplicateHeadOfStack
        cmp byte [buffer], '&'
        ;je 
        cmp byte [buffer], '|'
        ;je 
        cmp byte [buffer], 'n'
        ;je 
        cmp byte [buffer], '*'
        ;je 
        ;its a number so we need to parse it
        push eax
        call pushHexStringNumber
        add esp, 4
        ;add to the stack
        jmp calcLoop

    endCalcLoop:
        freeStack
        mov eax, [itemsInStack] ; TODO: we need to return the number of operations performed, not current items in stack
        ret

duplicateHeadOfStack:
    mov ebp, esp

    callReturn popNodeFromOperandStack ; TODO: To be implemented
    cmp eax, 0 ; Popping node from operand stack failed
    je duplicateHeadOfStackEnd

    ; Push the popped node back to the operand stack
    mov ebx, eax ; ebx = Address of the popped node
    pushReturn
    push ebx
    call pushNodeToOperandStack ; Must succeed, because we've just popped this item
    add esp, 4
    popReturn
    
    callReturn createNodeOnOperandStack
    cmp eax, 0 ; Creating node on operand stack failed
    je duplicateHeadOfStackEnd

    duplicateHeadOfStackLoop:
        ; eax will be the "temporary" register
        mov edx, eax ; edx = Address of the new node
        mov eax, [ebx + NODEVALUE]
        mov [edx + NODEVALUE], eax
        
        mov ebx, [ebx + NEXTNODE]
        cmp ebx, 0
        je duplicateHeadOfStackEnd
        
        callReturn createNode
        mov [edx + NEXTNODE], eax
        mov edx, eax
        jmp duplicateHeadOfStackLoop

    duplicateHeadOfStackEnd:
        mov esp, ebp
        jmp calcLoop

; X|Y with X being the top of operand stack and Y the element next to x in the operand stack.
bitwiseOr:
    mov ebp, esp
    push ebp ; Backup
    call popTwoItemsFromStack
    pop ebp
    cmp eax, 0
    je bitwiseOrEnd

    mov ecx, eax
    ; ebx = X, ecx = Y
    callReturn createNodeOnOperandStack ; Must succeed, we've just popped 2 items
    bitwiseOrLoop:
    ; eax = New node
    ; edx = temporary register
        mov dl, [ebx + NODEVALUE]
        mov [eax + NODEVALUE], dl
        mov dl, [ecx + NODEVALUE]
        or [eax + NODEVALUE], dl

        mov ebx, [ebx + NEXTNODE]
        mov ecx, [ecx + NEXTNODE]
        
        cmp ebx, 0
        je bitwiseOrFinalLoop

        cmp ecx, 0
        je FlipRegsBeforeBitwiseOrFinalLoop

        mov edx, eax
        callReturn createNode
        mov [edx + NEXTNODE], eax
        jmp bitwiseOrLoop

    FlipRegsBeforeBitwiseOrFinalLoop:
        mov edx, ebx
        mov ebx, ecx
        mov ecx, edx

    bitwiseOrFinalLoop:
        cmp ecx, 0
        je bitwiseOrEnd

        mov edx, eax
        callReturn createNode
        mov [edx + NEXTNODE], eax
        
        mov dl, [ecx + NODEVALUE]
        mov [eax + NODEVALUE], dl
        
        mov ecx, [ecx + NEXTNODE]
        jmp bitwiseOrFinalLoop

    bitwiseOrEnd:
        mov esp, ebp
        jmp calcLoop


; numberOfHexDigits:
;     mov ebp, esp

;     ; Validate a new node can be created on stack
;     callReturn createNodeOnOperandStack
;     cmp eax, 0 ; Pushing failed
;     je numberOfHexDigitsEnd
;     callReturn popNodeFromOperandStack ; TODO: To be implemented
;     ; Must succeed, because we've just pushed an item

;     ; Now the stack is as it was before the beginning the function
;     callReturn popNodeFromOperandStack ; TODO: To be implemented
;     cmp eax, 0 ; Popping node from operand stack failed
;     je numberOfHexDigitsEnd
;     mov ebx, eax ; ebx = Popped node

;     callReturn createNodeOnOperandStack ; Must succeed, because we've just popped an item
;     ; New node initialized on stack with value 0

;     numberOfHexDigitsLoop:
;         cmp dword [ebx + NEXTNODE], 0
;         je numberOfHexDigitsLastLoop
        
;         callReturn createNodeOnOperandStack
;         mov byte [eax + NODEVALUE], 2
;         call add ; TODO: To be implemented
        
;         add2toDigitsCounter:
;         add byte byte [edx + NODEVALUE], 2

;                         mov [edx + NODEVALUE], eax
                        
;                         mov ebx, [ebx + NEXTNODE]
;                         cmp ebx, 0
;                         je duplicateHeadOfStackEnd
                        
;                         callReturn createNode
;                         mov [edx + NEXTNODE], eax
;                         mov edx, eax
;                         jmp duplicateHeadOfStackLoop

;         mov ebx, [ebx + NEXTNODE]
;         cmp ebx, 0
;         jne numberOfHexDigitsLoop

;     numberOfHexDigitsLastLoop:
;         ; TODO
;         mov al, [ebx + NODEVALUE]
;         shr al, 4
;         cmp al, 0 ; Only 1 hex digit

    
;     numberOfHexDigitsEnd:
;         mov esp, ebp
;         jmp calcLoop


; Get the number of bytes to read from the buffer, assuming it's a string representing a hex number.
; Convert the string to its numeric value and push it to the operand stack.
pushHexStringNumber:
    mov ebp, esp

    callReturn createNodeOnOperandStack
    cmp eax, 0 ; Creating node on operand stack failed
    je pushHexStringNumberEnd

    mov edx, eax ; edx = Address of the new node

    pushHexStringNumberStart:
    callReturn countLeadingZeros ; now eax = number of leading zeros
    
    convertBufferToNodes:
    mov ecx, [ebp+4] ; String length
    mov ebx, eax ; ebx = number of leading zeros
    sub ecx, ebx ; ecx = string length - leading zeros.
                 ; This is the number of remaining chars to read
    ; edx = address of current node

    ; If the number is 0
    cmp ecx, 0
    je pushHexStringNumberEnd

    convertBufferLoop:
        ; If only 1 char needs to be read
        cmp ecx, 1
        je convertSingleCharFromBuffer

        ; Else, read 2 chars
        pushValue [buffer + ebx + ecx - 2], [edx + NODEVALUE]

        ; If there are no more chars to read, jump end of function
        sub ecx, 2
        cmp ecx, 0
        jz pushHexStringNumberEnd

        callReturn createNode
        
        mov [edx + NEXTNODE], eax ; Set 'next' field of the previous node to point to the new one
        mov edx, eax
        jmp convertBufferLoop

    convertSingleCharFromBuffer:
        mov bx, [buffer + ebx]
        shl bx, 8 ; Fill with zeros
        pushValue bx, [edx + NODEVALUE]

    pushHexStringNumberEnd:
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

; Create a new node and try to push it to the end of operand stack.
; Returns 0 in eax in case of failure, or the new node's address.
createNodeOnOperandStack:
    mov ebp, esp

    callReturn createNode
    mov edx, eax ; edx = Address of the new node
    
    pushReturn
    push edx
    call pushNodeToOperandStack
    add esp, 4
    popReturn
    
    cmp eax, 0 ; Pushing to operand stack succeeded
    jz createNodeOnOperandStackFailure
    mov eax, edx
    ret

    createNodeOnOperandStackFailure:
    freeNode edx
    ret

; Get an address of a node and push it to the end of operand stack.
; Returns 1 in eax in case of success, and 0 in case of failure.
pushNodeToOperandStack:
    ; Check if stack is full
    mov eax, [itemsInStack]
    cmp [stackSize], eax
    jne unsafePushNode
    push overflowMsg
    call printf
    mov eax, 0
    ret

    ; Push to the stack
    unsafePushNode:
    mov ebx, [esp+4]
    mov ecx, [stack]
    mov [ecx + 4 * eax], ebx
    inc byte [itemsInStack]
    mov eax, 1
    ret

; Pop 2 items from the stack and place the address of top in ebx and the second from top in eax.
; In case of failure, 0 is returned in eax and in ebx
popTwoItemsFromStack:
    mov ebp, esp

    callReturn popNodeFromOperandStack ; TODO: To be implemented
    cmp eax, 0
    je popTwoItemsFromStackEnd ; In case of failure
    mov ebx, eax

    callReturn popNodeFromOperandStack ; TODO: To be implemented
    cmp eax, 0
    jne popTwoItemsFromStackEnd ; In case of success

    ; If second pop failed, push back the first node
    pushReturn
    push ebx
    call pushNodeToOperandStack ; Must succeed, because we've just popped this item
    add esp, 4
    popReturn

    mov eax, 0
    ret

<<<<<<< HEAD
    popTwoItemsFromStackEnd:
        mov esp, ebp
        ret

=======
popNodeFromOperandStack:
    pushReturn
    mov edx, [itemsInStack]
    cmp edx, 0
    je error

    dec edx ; index starts at 0
    mov ebx, [stack]
    mov ecx, [ebx + edx * 4] ;ecx has the pointer to the last node  
    mov eax, 4
    mul edx
    add ebx, eax
    mov dword[ebx] ,0 ;the last place has null now
    mov eax, ecx
    dec byte [itemsInStack]
    jmp end

    error:
    mov eax, 0
    print illegalPop, 48

    end:
    popReturn
    ret
>>>>>>> master
