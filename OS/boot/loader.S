%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR

    LOADER_STACK_TOP equ LOADER_BASE_ADDR   ; loader在保护模式下的栈指针地址,esp

    ;jmp loader_start

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

    ;total_mem_bytes用于保存内存容量,以字节为单位,此位置比较好记
    ;当前偏移loader.bin文件头0x200字节,loader.bin的加载地址是0x900,
    ;故total_mem_bytes内存中的地址是0xb00.将来在内核中会引用此地址
    total_mem_bytes dd 0

    gdt_ptr dw GDT_LIMIT    ;定义加载进入GDTR的数据，前2字节是gdt界限，后4字节是gdt起始地址
            dd  GDT_BASE    ;dd: define double words

    ;人工对齐:total_mem_bytes 4字节 + gdt_ptr 6字节 + ards_buf 244字节 + ards_nr 2字节，共256字节
    ards_buf times 244 db 0 ;记录内存大小的缓冲区
    ards_nr dw  0   ;记录ARDS结构体数量

    ;loadermsg db '2 loader in real.'

    loader_start:
        ;----------------- int 15h eax = 0000E820h, edx = 534D4150h('SMAP')获取内存布局------
        xor ebx, ebx            ;xor 异或运算, 第一次调用将eb置0
        mov edx, 0x534d4150     ;edx只赋值一次,循环体中不会改变
        mov di, ards_buf        ;di指向ARDS缓冲区

        .e820_mem_get_loop:     ;循环获取每个ARDS内存范围描述结构
            mov eax, 0x0000e820 ;执行int 0x15后,eax值变为0x534d4150,所以每次执行int前都要更新为子功能号 
            mov ecx, 20         ;ARDS地址范围描述符结构大小是20字节
            int 0x15
            jc .e820_failed_so_try_e801 ;若cf位为1则有错误发生，尝试0xe801子功能
            add di, cx                  ;使di增加20字节指向缓冲区中下一个ARDS结构位置
            inc word [ards_nr]          ;ARDS增加1

            cmp ebx, 0                  ;若ebx为0且cf不为1，则说明ards全部返回，当前已是最后一个
            jnz .e820_mem_get_loop      ;如果cmp指令两个数不相等，则zf（zero flag）寄存器就为0，表示两数不相等,没有产生0结果，
                                        ;所以zf为false,即0,没有0结果所以不为0则循环获取
            
            ;在所有ards结构中，找出(base_add_low + length_low)的最大值,即内存的容量
            mov cx, [ards_nr]           ;遍历每一个ARDS结构体,循环次数是ARDS的数量
            mov ebx, ards_buf
            xor edx, edx                ;用edx记录最大值，此处先清零

        .find_max_mem_area:             ;无须判断type是否为1，最大的内存块一定是可被使用
            mov eax, [ebx]              ;base_add_low
            add eax, [ebx+8]            ;base_add_low + length_low
            add ebx, 20                 ;指向下一个ards
            cmp edx, eax                ;将当前ards的内存大小(eax)与当前存储的最大值（edx）比较
            jge .next_ards              ;如果eax < edx，说明此块ards不是最大的，继续查找下一块
            mov edx, eax                ;如果当前的ards的内存大小比记录的最大值（edx）大, 更新记录值（edx）
        .next_ards:
            loop .find_max_mem_area
            jmp .mem_get_ok             ;获取内存容量结束

        ;------------ int 15h ax=E801h 获取内存大小,最大支持4G ----------------------
        ;返回后，ax cx 值一样,以KB为单位,bx dx值一样,以64KB为单位
        ;在ax和cx寄存器中为低16M,在bx和dx寄存器中为16MB到4G
        ;-------------------------------------------------------------
        .e820_failed_so_try_e801:
            mov ax, 0xe801
            int 15
            jc .e801_failed_so_try88    ;cf为1，调用出错尝试 0x88子功能，若没有错cf为0，不跳转

            ; 1 先算出低15M的内存,ax和cx中是以KB为单位的内存数量，将其转换为以byte为单位
            ;乘数在eax,即内存数量，积高16位在edx, 低16位在eax
            mov cx, 0x400               ;0x400=1024
            mul cx                      ;cx与ax的值相乘
            shl edx, 16                 ;左移16位，将积的高16位放到edx高16位
            and eax, 0x0000ffff         ;目的是为了将eax的高16为都置0
            or edx,eax                  ;将积的高16位和低16位拼到一起合成得到完整的32位积
            add edx, 0x100000           ;edx比实际少1M,故要加1MB
            mov esi, edx                ;先把低15MB的内存容量存入esi寄存器备份

            ; 2再将16MB以上的内存转换为byte为单位，寄存器bx和dx中是以64KB为单位的内存数量
            xor eax, eax
            mov ax, bx
            mov ecx, 0x10000            ;0x10000十进制为64KB
            mul ecx                     ;32位乘法，默认的被乘数是eax,积为64位，高32位存入edx,低32位存入eax
            add esi, eax                ;由于此方法只能测出4G以内的内存，故32位eax足够了，edx肯定为0，只加eax便可
            mov edx, esi                ;edx为总内存大小
            jmp .mem_get_ok

        ;----------int 15h ah=0x88 获取内存大小，只能获取64M之内 -------------------
        ;返回：AX -> 以1kb为单位大小，内存空间1MB之上的连续单位数量，不包括低端1MB内存，
        ;故内存大小要加上1MB
        .e801_failed_so_try88:
            ;int 15后，ax存入的是以kb为单位的内存容量
            mov ah, 0x88
            int 0x15
            jc .error_hlt
            and eax, 0x0000ffff

            ;16位乘法，被乘数是ax,积为32位，积的高16位在dx中，积的低16位在ax中
            mov cx, 0x400               ;0x400 = 1024, 将ax中的内存容量换为byte位单位
            mul cx
            shl edx, 16
            or edx, eax                 ;将积的高16位和低16位拼到一起合成得到完整的32位积
            add edx, 0x100000           ;0x88子功能只会返回1MB以上的内存，故要加上低1MB的内存才是实际的内存

        .mem_get_ok:
            mov [total_mem_bytes], edx  ;将内存换为byte单位后存入total_mem_bytes处

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
        
        .error_hlt:
            hlt                     ;出错则挂起，处理器暂停，直到出现中断或复位信号才继续

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