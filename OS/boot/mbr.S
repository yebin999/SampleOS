; 主引导程序
;功能：在屏幕上打印字符串"1 MBR",背景色为绿色，前景色为红色
;LOADER_BASE_ADDR equ 0xA000
;LOADER_START_SECTOR equ 0x2
;-------------------------------------------------------

%include "boot.inc"
section MBR vstart=0x7c00

    ; 初始化段寄存器，BIOS通过jmp 0:0x7c00跳转到mbr，故此时cs的值为0
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov sp, 0x7c00 
    ; 这个时候 ds = es = ss = 0 栈指针指向MBR开始位置
    ; 0x7c00以下暂时是安全的区域，就把当作mbr的栈来用
    ; 初始化段寄存器结束
    mov ax, 0xb800
    ; 实模式下内存分段访问的策略是"段基址*16 + 段内偏移地址"  
    ; B8000~BFFFF 32KB 用于文本模式显示适配器
    ;给寄存器的值要除以16，所以是b800 不是 b8000
    mov gs,ax


    ; 清屏 利用0x06号功能，上卷全部行，则可清屏。
    ; -----------------------------------------------------------
    ;INT 0x10   功能号:0x06	   功能描述:上卷窗口
    ;------------------------------------------------------
    ;输入：
    ;AH 功能号= 0x06
    ;AL = 上卷的行数(如果为0,表示全部)
    ;BH = 上卷行属性
    ;(CL,CH) = 窗口左上角的(X,Y)位置
    ;(DL,DH) = 窗口右下角的(X,Y)位置
    ;无返回值：
    mov ax, 0x600 ; 设置AH为06， 即功能号= 0x06, 上卷全部行数
    mov bx, 0x700
    mov cx, 0     ; 窗口左上角的(0,0)位置
    mov dx, 0x184f ;窗口右下角的(24,79)位置, 因为默认为80x25的VGA文本模式, 0x18=24, 0x4f=79
    int 0x10
    ; 清屏结束

    ;输出背景色绿色，前景色红色，并且跳动的字符串"1 MBR"

    mov byte [gs:0x00], '1'
    mov byte [gs:0x01], 0xA4 ; A (1010)表示绿色背景闪烁, 4表示前景色为红色

    mov byte [gs:0x02], ' '
    mov byte [gs:0x03], 0xA4

    mov byte [gs:0x04], 'M'
    mov byte [gs:0x05], 0xA4

    mov byte [gs:0x06], 'B'
    mov byte [gs:0x07], 0xA4

    mov byte [gs:0x08], 'R'
    mov byte [gs:0x09], 0xA4

    mov eax,LOADER_START_SECTOR ;起始扇区lba地址
    mov bx,LOADER_BASE_ADDR ;写入的地址
    mov cx,4    ;待读入的扇区数
    call rd_disk_m_16   ;以下读取程序的起始部分(一个扇区)

    jmp LOADER_BASE_ADDR + 0x300        ;跳过数据段，跳跃到代码区

    ;---------------------------------
    ;功能：读取硬盘n个扇区
    ;----------------------------------
    rd_disk_m_16:
    
    
        mov esi,eax ; 备份eax
        mov di,cx   ; 备份cx

;读写硬盘：
;第1步：设置要读取的扇区数
        mov dx,0x1f2
        mov al,cl
        out dx,al   ;读取的扇区数
        mov eax,esi ;恢复ax

;第2步：将LBA地址存入0x1f3~0x1f6
        ;LBA地址7~0位写入端口0x1f3
        mov dx,0x1f3
        out dx,al

        ;LBA地址15~8位置写入端口0x1f4
        mov cl,8
        shr eax,cl
        mov dx,0x1f4
        out dx,al

        ;LBA地址23~16为写入端口0x1f5
        shr eax,cl
        mov dx,0x1f5
        out dx,al

        shr eax,cl
        and al,0x0f ; lba第24~27位
        or al,0xe0  ;设置7~4位为1110,表示lba模式
        mov dx,0x1f6
        out dx,al

;第3步：向0x1f7端口写入读写命令,0x20
        mov dx,0x1f7
        mov al,0x20
        out dx,al

;第4步：检测硬盘状态
        .not_ready:
            ;同一端口，写时表示写入命令，读时表示读入硬盘状态
            nop
            in al,dx
            and al,0x88 ;第4位为1表示硬盘控制器已准备好数据传输
                        ;第7位为1表示硬盘忙
            cmp al,0x08
            jnz .not_ready ;若为准备好，继续等
;第5步：从0x1f0端口读取数据
        mov ax,di   ;di=1,为要读取的扇区数，一个扇区有512字节，每次读入一个字共需di*512/2次
        mov dx,256
        mul dx  ;被乘数隐含在al或ax里的值，如果操作数是8位，被乘数就是al里的值，乘积就是16位，位于ax寄存器
                ;如果操作数是16位，被乘数就是ax寄存器里的值，乘积就是32位，积的高16位在dx寄存器，低16位在ax寄存器
        mov cx,ax   ;因为积比较小，所以取低16位就可以
        mov dx,0x1f0
        .go_on_read:
            in ax,dx
            mov [bx],ax ;[bx] = ds*16 + bx,我们在前面已经将ds置0过,所以[bx]=bx
            add bx,2
            loop .go_on_read
        ret
   
    times 510-($-$$) db 0 	;$本行指令的地址,$$是本section的起始地址, times伪指令，重复执行db 0 指令 510-($-$$)次
    db 0x55,0xaa 	;在最后写入魔数 0x55 0xaa

