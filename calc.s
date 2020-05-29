section .bss
    stack: resd 1 ; Address of the operand stack
    buffer: resb 81 ; The input buffer - 81 bc \n is also saved 

section .rodata
    newLine: db 10, 0 ; '\n'
    printNumberFormat: db "%d", 0
    printNumberHexFormat: db "%X", 0
    printStringFormat: db "%s", 10, 0	; format string

    calcMsg: db "calc: ", 0
    overflowMsg: db "Error: Operand Stack Overflow", 10, 0
    illegalPop: db "Error: Insufficient Number of Arguments on Stack", 10, 0
    
    NODEVALUE: equ 0 ; Offset of the value byte from the beginning of a node
    NEXTNODE: equ 1 ; Offset of the next-node field (4 bytes) from the beginning of a node

section .data
    debug: db 0
    sumN: db 0
    stackSize: db 5 ; Operand stack size (default: 5. Min: 2, Max: 0xFF)
    itemsInStack: db 0 ; Current items in stack (start value: 0)
    operationsPerformed: dd 0 ; dword
    nodeToFree: dd 0 ;ptr
    nodeToFree2: dd 0 ;ptr
    

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
    extern stdout
    extern stderr
 
%macro print 1
pushad
push %1
call printf
add esp, 4
push dword [stdout]
call fflush
add esp, 4
popad
%endmacro

%macro print 2
pushad
push %1
call printf
add esp, 4
push dword %2
call fflush
add esp, 4
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
        cmp byte [itemsInStack], 0
        je endFreeLoop
        callReturn popNodeFromOperandStack
        freeLinkedListAt eax
        jmp freeLoop
    endFreeLoop:
    freeNode [stack]
    popad
%endmacro

%macro freeNode 1
push dword %1
call free
add esp, 4
%endmacro

%macro freeLinkedListAt 1
pushad
push %1
call freeLinkedList
add esp, 4
popad
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

%macro updateCounter 0
add dword [operationsPerformed], 1
%endmacro

%macro bufferSwitchToNull 0
    pushad
    mov esi, buffer
    %%loopNull:
        cmp byte [esi], 10
        je %%endNullLoop
        add esi, 1
        jmp %%loopNull
    %%endNullLoop:
    mov byte [esi], 00 
    popad
%endmacro

%macro printDebug 1
    pushad
    push dword %1
    push dword printStringFormat
    push dword [stderr]
    call fprintf
    add esp, 12
    push dword [stderr]
    call fflush
    add esp, 4
    popad
%endmacro

%macro printDebugResult 0
    pushad
    mov ebx, [stack]
    mov edx, 0
    mov dl, [itemsInStack]
    dec dl
    push dword [stderr]
    push dword [ebx + edx * 4]
    call popAndPrintRecursion
    add esp, 8
    print newLine, [stderr]
    popad
%endmacro

%macro endOperation 1
    cmp byte [debug], 1
    jne %1
    printDebugResult
%endmacro

main:
    mov ebp, esp

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
    callMyCalc: callReturn myCalc
    ; Print number of operations performed
    ; Assuming operations performed is in eax
    pushad
    push eax
    push printNumberHexFormat
    call printf
    add esp, 8
    popad
    print newLine

    finishProgram:
        mov esp, ebp
        mov eax, 0 ; Program exit code
        ret

myCalc:
    mov eax, 4 
    push eax
    mov eax, [stackSize] ; stack size - we need to check somewhere else if the itemsInStack is valid
    inc eax ; Allocate an extra space to be used in numberOfHexDigits.
    push eax   
    call calloc        
    add esp, 8 ;cleaning the stack from locals
    mov dword[stack], eax ; eax has the pointer to the start of the stack

    calcLoop:
        print calcMsg
        pushReturn
        mov eax, 3 ; lines 82-86 reads the input to the buffer - eax has the number of bytes that have been recived - the input is valid no need to check
        mov ebx, 0
        mov ecx, buffer
        mov edx, 81
        int 0x80 
        popReturn

        bufferSwitchToNull 

        calcCallOperation:
        dec eax ; length of the char without the \n

        cmp byte [buffer], 'q'
            jne checkPlus
            jmp endCalcLoop
        
        checkPlus: cmp byte [buffer], '+'
            jne checkP
            callReturn sum
            jmp calcLoop
        
        checkP: cmp byte [buffer], 'p'
            jne checkD
            callReturn popAndPrint
            jmp calcLoop

        checkD: cmp byte [buffer], 'd'
            jne checkAnd
            callReturn duplicateHeadOfStack
            jmp calcLoop

        checkAnd: cmp byte [buffer], '&'
            jne checkOr
            callReturn bitwiseAnd
            jmp calcLoop

        checkOr: cmp byte [buffer], '|'
            jne checkN
            callReturn bitwiseOr
            jmp calcLoop

        checkN: cmp byte [buffer], 'n'
            jne checkNumber
            callReturn numberOfHexDigits
            jmp calcLoop

        ;its a number so we need to parse it
        checkNumber:
            push eax
            call pushHexStringNumber
            add esp, 4
            ;add to the stack
            jmp calcLoop

    endCalcLoop:
        freeStack
        mov eax, [operationsPerformed]
        ret

popAndPrint:
    mov ebp, esp
    updateCounter
    
    callReturn popNodeFromOperandStack
    cmp eax, 0 ; Popping node from operand stack failed
    je popAndPrintEnd
    mov ebx, eax ; ebx = The popped node

    pushad
    push dword [stdout]
    push ebx
    call popAndPrintRecursion
    add esp, 8
    popad
    
    print newLine
    freeLinkedListAt ebx
    
    popAndPrintEnd:
        mov esp, ebp
        ret

popAndPrintRecursion:
    mov ebp, esp
    push dword 0 ; Will be the value to print
    
    mov ebx, [ebp+4]
    mov cx, [ebx + NODEVALUE]
    mov edx, [ebx + NEXTNODE]
    cmp edx, 0
    je lastPopAndPrintRecursion

    pushReturn
    push dword [ebp+8]
    push edx
    call popAndPrintRecursion
    add esp, 8
    popReturn

    printNode:
        pushReturn
        push cx
        call byteToHexString
        add esp, 2
        popReturn
        
        and eax, 0x0000FFFF
        mov [ebp-4], eax
        mov edx, ebp
        sub edx, 4
        print edx, [ebp+8]
    
    mov esp, ebp
    ret

    lastPopAndPrintRecursion:
        pushReturn
        push cx
        call byteToHexString
        add esp, 2
        popReturn

        and eax, 0x0000FFFF
        cmp al, 0x30 ; A leading zero
        je printLowerCharOfValue
        
        mov [ebp-4], eax
        mov edx, ebp
        sub edx, 4
        print edx, [ebp+8]
        jmp lastPopAndPrintRecursionEnd
        
        printLowerCharOfValue:
            shr eax, 8
            mov [ebp-4], eax
            mov edx, ebp
            sub edx, 4
            print edx, [ebp+8]
        
        lastPopAndPrintRecursionEnd:
            mov esp, ebp
            ret

duplicateHeadOfStack:
    mov ebp, esp
    updateCounter

    callReturn popNodeFromOperandStack
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
        je duplicateHeadOfStackEndDebug
        
        callReturn createNode
        mov [edx + NEXTNODE], eax
        mov edx, eax
        jmp duplicateHeadOfStackLoop
    
    duplicateHeadOfStackEndDebug:
        endOperation duplicateHeadOfStackEnd
    duplicateHeadOfStackEnd:
        mov esp, ebp
        ret

; X|Y with X being the top of operand stack and Y the element next to x in the operand stack.
bitwiseOr:
    mov ebp, esp
    updateCounter

    push ebp ; Backup
    call popTwoItemsFromStack
    pop ebp
    cmp eax, 0
    je bitwiseOrEnd

    mov ecx, eax
    ; ebx = X, ecx = Y
    mov [nodeToFree], ecx
    mov [nodeToFree2], ebx

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
        je bitwiseOrEndFree

        mov edx, eax
        callReturn createNode
        mov [edx + NEXTNODE], eax
        
        mov dl, [ecx + NODEVALUE]
        mov [eax + NODEVALUE], dl
        
        mov ecx, [ecx + NEXTNODE]
        jmp bitwiseOrFinalLoop
    
    bitwiseOrEndFree:
        freeLinkedListAt dword [nodeToFree]
        freeLinkedListAt dword [nodeToFree2]
        endOperation bitwiseOrEnd
    bitwiseOrEnd:
        mov esp, ebp
        ret

; For internal use of numberOfHexDigits
%macro numberOfHexDigitsAdd 1
callReturn unsafeCreateNodeOnOperandStack
mov byte [eax + NODEVALUE], %1
mov byte [sumN], 1 ;turn on the flag so it won't print in debug the sum
callReturn sum
mov byte [sumN], 0 ;turn off the flag
dec dword [operationsPerformed] ; sum op. wont count
%endmacro

; Number of hexadecimal digits functionallity
numberOfHexDigits:
    mov ebp, esp
    updateCounter

    callReturn popNodeFromOperandStack
    cmp eax, 0 ; Popping node from operand stack failed
    je numberOfHexDigitsEnd
    mov edx, eax ; edx = Popped node (backup)
    mov ebx, eax ; ebx = Popped node (for looping)

    mov [nodeToFree], edx
    callReturn createNodeOnOperandStack ; Must succeed, because we've just popped an item
    ; New node initialized on stack with value 0

    numberOfHexDigitsLoop:
        cmp dword [ebx + NEXTNODE], 0
        je numberOfHexDigitsLastLoop
        
        numberOfHexDigitsAdd 2

        mov ebx, [ebx + NEXTNODE]
        cmp ebx, 0
        jne numberOfHexDigitsLoop

    numberOfHexDigitsLastLoop:
        cmp byte [ebx + NODEVALUE], 0x10
        jb addOneToNumberOfHexDigits

        numberOfHexDigitsAdd 1
        
        addOneToNumberOfHexDigits:
            numberOfHexDigitsAdd 1

    ; Free the popped linked list
    freeLinkedListAt edx
    endOperation numberOfHexDigitsEnd ;for debug
    numberOfHexDigitsEnd:
        mov esp, ebp
        ret

; Get the number of bytes to read from the buffer, assuming it's a string representing a hex number.
; Convert the string to its numeric value and push it to the operand stack.
pushHexStringNumber:
    mov ebp, esp

    cmp byte [debug], 1
    jne notDebug
    printDebug buffer

    notDebug:
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

; Get a byte of data and return a hexadecimal digit string representing it.
; Result stored in ax.
byteToHexString:
    mov ebp, esp

    mov dx, [esp+4]
    push dx
    call nibbleToHexChar
    mov ch, al

    shr dx, 4
    push dx
    call nibbleToHexChar
    mov cl, al

    mov ax, cx
    mov esp, ebp
    ret

; Get a nibble (4 bits) of data and return a hexadecimal char string representing it.
; Result stored in al.
nibbleToHexChar:
    mov al, [esp+4]
    and al, 0x0F
    cmp al, 0xA
    jl addDecimalAsciiOffset
    add al, 0x7
    addDecimalAsciiOffset:
    add al, 0x30
    ret

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
    
    cmp eax, 0 ; Pushing to operand stack failed
    jz createNodeOnOperandStackFailure
    mov eax, edx
    ret

    createNodeOnOperandStackFailure:
    freeNode edx
    mov eax, 0
    ret

; Create a new node and push it to the end of operand stack.
; Use only in numberOfHexDigits
unsafeCreateNodeOnOperandStack:
    callReturn createNode
    mov edx, eax ; edx = Address of the new node
    
    pushReturn
    push edx
    call unsafePushNode
    add esp, 4
    popReturn    
    mov eax, edx
    ret

; Get an address of a node and push it to the end of operand stack.
; Returns 1 in eax in case of success, and 0 in case of failure.
pushNodeToOperandStack:
    ; Check if stack is full
    mov eax, 0 ; Reset register
    mov al, [itemsInStack]
    cmp [stackSize], al
    jne unsafePushNode
    print overflowMsg
    mov eax, 0
    ret

    ; Push to the stack
    unsafePushNode:
    ; Next 2 lines are duplicated so unsafePushNode will be able to be called independently
    mov eax, 0 ; Reset register
    mov al, [itemsInStack]

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

    callReturn popNodeFromOperandStack
    cmp eax, 0
    je popTwoItemsFromStackEnd ; In case of failure
    mov ebx, eax

    callReturn popNodeFromOperandStack
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

    popTwoItemsFromStackEnd:
        mov esp, ebp
        ret

popNodeFromOperandStack:
    pushReturn
    mov edx, 0 ; Reset register
    mov dl, [itemsInStack]
    cmp edx, 0
    je popNodeFromOperandStackError

    dec edx ; index starts at 0
    mov ebx, [stack]
    mov ecx, [ebx + edx * 4] ;ecx has the pointer to the last node
    
    mov dword [ebx + edx * 4] , 0
    
    mov eax, ecx
    dec byte [itemsInStack]
    jmp popNodeFromOperandStackEnd

    popNodeFromOperandStackError:
    mov eax, 0
    print illegalPop

    popNodeFromOperandStackEnd:
    popReturn
    ret

;X&Y with X being the top of operand stack and Y the element next to x in the operand stack.
bitwiseAnd:
    mov ebp, esp
    updateCounter

    push ebp ; Backup
    call popTwoItemsFromStack
    pop ebp
    cmp eax, 0
    je bitwiseAndEnd

    mov ecx, eax
    ; ebx = X, ecx = Y
    mov [nodeToFree], ecx
    mov [nodeToFree2], ebx

    callReturn createNodeOnOperandStack ; Must succeed, we've just popped 2 items
    bitwiseAndLoop:
        ; eax = New node
    ; edx = temporary register
        mov dl, [ebx + NODEVALUE]
        mov [eax + NODEVALUE], dl
        mov dl, [ecx + NODEVALUE]
        and [eax + NODEVALUE], dl

        mov ebx, [ebx + NEXTNODE]
        mov ecx, [ecx + NEXTNODE]
        
        cmp ebx, 0
        je bitwiseAndEndFree

        cmp ecx, 0
        je bitwiseAndEndFree

        mov edx, eax
        callReturn createNode
        mov [edx + NEXTNODE], eax
        jmp bitwiseAndLoop
    
    bitwiseAndEndFree:
        freeLinkedListAt dword [nodeToFree]
        freeLinkedListAt dword [nodeToFree2]
        endOperation bitwiseAndEnd
    bitwiseAndEnd:
        mov esp, ebp
        ret    

sum:
    mov ebp, esp
    updateCounter

    ;add esp, 8
    push ebp ; Backup
    call popTwoItemsFromStack
    pop ebp
    cmp eax, 0
    je sumEnd

    mov ecx, eax
    ; so we can free both of these nodes
    mov [nodeToFree], ecx
    mov [nodeToFree2], ebx
    ; ebx = X, ecx = Y
    callReturn createNodeOnOperandStack
    clc ; reset the CF value
    pushfd
    mov edx, 0 ;reset edx
    sumLoop:
        popfd
        mov byte dl,[ebx + NODEVALUE]
        mov byte [eax + NODEVALUE], dl
        mov byte dl,[ecx + NODEVALUE]
        adc byte [eax + NODEVALUE], dl
        pushfd
        
        mov ebx, [ebx + NEXTNODE]
        mov ecx, [ecx + NEXTNODE]

        mov edx, ecx
        cmp ebx, 0
        je sumRest

        mov edx, ebx
        cmp ecx, 0
        je sumRest

        mov edx, eax ;so we can save the new node value
        callReturn createNode
        mov [edx + NEXTNODE], eax
        jmp sumLoop

        sumRest: ;edx now has the other var
            cmp edx, 0 ;both x, y are done
            je lastCarry
        
            lastSumLoop: ;loop till edx is empty
                mov ecx, eax
                callReturn createNode
                mov [ecx + NEXTNODE], eax

                popfd
                mov cl, [edx + NODEVALUE]
                adc [eax + NODEVALUE], cl
                mov edx, [edx + NEXTNODE]
                pushfd
                jmp sumRest

            lastCarry:
                popfd
                jnc sumEndFree ; checking if we have carry to add
                mov edx, eax
                callReturn createNode
                mov [edx + NEXTNODE], eax
                inc byte [eax + NODEVALUE]
                
    sumEndFree:
        freeLinkedListAt dword [nodeToFree]
        freeLinkedListAt dword [nodeToFree2]
        cmp byte [sumN], 1
        je sumEnd
        endOperation sumEnd
    sumEnd:
        mov esp, ebp
        ret
