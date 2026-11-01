.global _start
.text
_start:
    vzeroupper
    xor %edi, %edi
    mov $60, %eax
    syscall
