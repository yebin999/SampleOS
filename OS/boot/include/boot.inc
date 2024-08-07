;----------------loader 和 kernel-------------
LOADER_BASE_ADDR equ 0x900
LOADER_START_SECTOR equ 0x2

;------------ gdt 描述符属性 ----------------
DESC_G_4K equ 1_00000000000000000000000b ;GDT高32位中的第23位G（从第0位开始）为1,表示段界限的单位是4KB
DESC_D_32 equ 1_0000000000000000000000b ;GDT高32位中的第22位（从第0位开始）为1（对于代码段来说是D）,表示指令中的有效地址及操作数是32位
DESC_L equ 0_000000000000000000000b ;GDT高32位中的第21位（从第0位开始）为0（L）,表示32位代码段,如果是1表示64位代码段
DESC_AVL equ 0_00000000000000000000b ;GDT高32位中的第20位（从第0位开始）为0（AVL）,CPU不用此位，暂置为0
DESC_LIMIT_CODE2 equ 1111_0000_0000_0000_0000b  ;段界限: GDT高32位19~16位
DESC_LIMIT_DATA2 equ DESC_LIMIT_CODE2
DESC_LIMIT_VIDEO2 equ 0000_0000_0000_0000_000b ;定义我们要操作显存时对应的段描述符的高32位中16~19段界限为全0
DESC_P equ 1_000000000000000b
DESC_DPL_0  equ 00_0000000000000b
DESC_DPL_1  equ 01_0000000000000b
DESC_DPL_2  equ 10_0000000000000b
DESC_DPL_3  equ 11_0000000000000b
DESC_S_CODE equ 1_000000000000b ;S:GDT高32位的第13位(从第0位开始),1:表示数据段, 0:表示系统段
DESC_S_DATA equ DESC_S_CODE
DESC_S_sys equ 0_000000000000b ;S:GDT高32位的第13位(从第0位开始),1:表示数据段, 0:表示系统段
DESC_TYPE_CODE equ 1000_00000000b   ;TYPE: x=1,c=0,r=0,a=0 代码段是可执行的,非一致性,不可读,已访问位a清0
DESC_TYPE_DATA equ 0010_00000000b   ;TYPE: x=0,e=0,w=1,a=0 数据段是不可执行的,向上扩展的,可写,已访问位a清0

;HIGH4表示高4字节
DESC_CODE_HIGH4 equ (0x00 << 24) + DESC_G_4K + DESC_D_32 + \
DESC_L + DESC_AVL + DESC_LIMIT_CODE2 + \
DESC_P + DESC_DPL_0 + DESC_S_CODE + \
DESC_TYPE_CODE + 0x00

DESC_DATA_HIGH4 equ (0x00 << 24) + DESC_G_4K + DESC_D_32 + \
DESC_L + DESC_AVL + DESC_LIMIT_DATA2 + \
DESC_P + DESC_DPL_0 + DESC_S_DATA + \
DESC_TYPE_DATA + 0x00

DESC_VIDEO_HIGH4 equ (0x00 << 24) + DESC_G_4K + DESC_D_32 + \
DESC_L + DESC_AVL + DESC_LIMIT_VIDEO2 + \
DESC_P + DESC_DPL_0 + DESC_S_DATA + \
DESC_TYPE_DATA + 0x0b

;---------- 选择子属性 -----------------------
RPL0 equ 00b
RPL1 equ 01b
RPL2 equ 10b
RPL3 equ 11b
TI_GDT  equ 000b
TI_LDT  equ 100b
