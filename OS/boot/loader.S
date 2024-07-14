%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR
jmp loader_start

;构建gdt及其内部的描述符
;GDT_BASE,CODE_DESC,DATA_STACK_DESC,VIDEO_DESC是构造的四个段描述符
;GDT中的第0个描述符不可用(即GDT_BASE),但必须要有
GDT_BASE:   
    dd  0x00000000
    dd  0x00000000

CODE_DESC:
    dd  0x0000FFFF
    dd  DESC_CODE_HIGH4

DATA_STACK_DESC:
    dd  0x0000FFFF
    dd  DESC_DATA_HIGH4

VIDEO_DESC:
    dd  0x80000007  ;limit=(0xbffff-0xb8000)/4k=0x7
    dd  DESC_VIDEO_HIGH4 ;此时dpl已经改为0

    GDT_SIZE    equ $ - GDT_BASE
    GDT_LIMIT   equ GDT_SIZE-1
    times   60  dq  0           ;dq用来定义8字节数据, 此处预留60个描述符的空位
    SELECTOR_CODE   equ (0x0001<<3)+TI_GDT+RPL0 ;相当于(CODE_DESC - GDT_BASE)/8 + TI_GDT + RPL0
    SELECTOR_DATA   equ (0x0002<<3)+TI_GDT+RPL0 ;同上
    SELECTOR_VIDEO   equ (0x0003<<3)+TI_GDT+RPL0 ;同上

gdt_ptr dw GDT_LIMIT    ;定义加载进入GDTR的数据，前2字节是gdt界限，后4字节是gdt起始地址
        dd  GDT_BASE

loadermsg db '2 loader in real.'

loader_start:
    ;-----------------------------------------------
    ;INT0x10    功能号：0x13    功能描述：打印字符串
    ;-----------------------------------------------
    ;输入：
    ;AH 子功能号=13H
    ;BH = 页码
    ;CX＝字符串长度
    ;(DH、DL)＝坐标(行、列)
    ;ES:BP＝字符串地址 
    ;AL＝显示输出方式
    ;   0——字符串中只含显示字符，其显示属性在BL中。显示后，光标位置不变
    ;   1——字符串中只含显示字符，其显示属性在BL中。显示后，光标位置改变
    ;   2——字符串中含显示字符和显示属性。显示后，光标位置不变
    ;   3——字符串中含显示字符和显示属性。显示后，光标位置改变
    ;无返回值                        

    mov sp, LOADER_BASE_ADDR
    mov bp, loadermsg           ;ES:BP＝字符串地址
    mov cx, 17                  ;CX＝字符串长度
    mov ax, 0x1301              ;AH=13, AL=01h
    mov bx, 0x001f              ;页号为0（BH=0）， 蓝底粉红字（BL=1fh）
    mov dx, 0x1800              ;
    int 0x10                    ; 10h号中断

    ;-------------- 准备进入保护模式 ------------------------
    ;1 打开A20
    ;2 加载gdt
    ;3 将cr0的pe位置1

    in al, 0x92             ;----------打开A20--------------
    or al, 0000_0010B       ;将端口0x92的第一个位置置1
    out 0x92, al

    lgdt [gdt_ptr]          ;--------加载GDT----------------

    mov eax,cr0             ;--------cr0第0位置1
    or eax, 0x00000001
    mov cr0,eax

    jmp dword SELECTOR_CODE:p_mode_start    ;刷新流水线，CPU会将当前指令及其后面的几条指令同时放在流水线中重叠执行
                                            ;由于实模式下时，指令按照16位指令格式来译码，从此位置到p_mode_start之间
                                            ;既有16位指令，又有32位指令，所以把32位指令照16位指令译码就会出错
                                            ;解决问题的办法就是用无跳转指令清空流水线

[bits 32]
p_mode_start:
    mov ax, SELECTOR_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, LOADER_STACK_TOP
    mov ax, SELECTOR_VIDEO
    mov gs, ax

    mov byte [gs:160], 'P'      ;往显存第80个字符的位置（第2行首字符的位置）写入字符P
                                ;默认的文本显示模式是80*25，即每行是80个字符（0~79），每个字符占2字节
                                ;故传入偏移地址是80*2=160

    jmp $