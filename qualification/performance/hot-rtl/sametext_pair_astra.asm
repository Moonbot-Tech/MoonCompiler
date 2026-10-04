option casemap:none
.code

; Equal-length full UTF-16/ASCII-ignore-case content comparison.
; Preserve the paired exact-match path; examine individual code units only
; when a pair differs. No repeated managed-string header checks or ordering.
asm_sametext_pair_content proc
    test    r8, r8
    jz      equal_result
    lea     r8, [rcx+r8*2]
    sub     rdx, rcx
    lea     r9, [r8-2]
    cmp     rcx, r9
    jae     tail_char
pair_loop:
    mov     eax, dword ptr [rcx]
    mov     r10d, dword ptr [rcx+rdx]
    cmp     eax, r10d
    je      next_pair
    xor     r10d, eax
    test    r10w, r10w
    jz      high_char
    cmp     r10w, 20h
    jne     different_result
    movzx   r11d, ax
    or      r11d, 20h
    sub     r11d, 'a'
    cmp     r11d, 'z' - 'a'
    ja      different_result
high_char:
    shr     r10d, 16
    jz      next_pair
    cmp     r10d, 20h
    jne     different_result
    shr     eax, 16
    or      eax, 20h
    sub     eax, 'a'
    cmp     eax, 'z' - 'a'
    ja      different_result
next_pair:
    add     rcx, 4
    cmp     rcx, r9
    jb      pair_loop
tail_char:
    cmp     rcx, r8
    jae     equal_result
    movzx   eax, word ptr [rcx]
    movzx   r10d, word ptr [rcx+rdx]
    xor     r10d, eax
    jz      equal_result
    cmp     r10d, 20h
    jne     different_result
    or      eax, 20h
    sub     eax, 'a'
    cmp     eax, 'z' - 'a'
    ja      different_result
equal_result:
    mov     eax, 1
    ret
different_result:
    xor     eax, eax
    ret
asm_sametext_pair_content endp
end
