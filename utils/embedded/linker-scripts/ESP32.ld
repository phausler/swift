ENTRY(_start)

MEMORY {
  flash (rx!w) :
    ORIGIN = 0x40800250,
    LENGTH = 0x00400000
  ram (w!rx) :
    ORIGIN = 0x3FFE8000,
    LENGTH = 0x00200000
}

SECTIONS {
  .init : { *(.init*) } > flash
  .literal : { *(.literal*) } > flash
  .text : { *(.text*) } > flash
  .rodata : { *(.rodata*) } > flash
  .data : { *(.data*) } > ram
  .bss : { 
    __bss_start__ = .;
    *(.bss*) 
    . = ALIGN(8);
    __bss_end__ = .;
  } > ram

  PROVIDE( __end = __bss_end__ );

  PROVIDE (__heap_start = __end);
  PROVIDE (__heap_end = __stack_top - (DEFINED(__stack_size) ? __stack_size : 0x00001000));
  PROVIDE (__heap_size = __heap_end - __heap_start);

  .heap (NOLOAD) : {
    . += (DEFINED(__heap_size_min) ? __heap_size_min : 0);
  } >ram :ram

  .stack (NOLOAD) : {
    . += (DEFINED(__stack_size) ? __stack_size : 0x00001000);
  } >ram :ram

  PROVIDE(__stack_top = ORIGIN(ram) + LENGTH(ram));
}
