OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS {
  . = 0x80000000;
  .text.init : {
    *(.text.init)
  }

  . = ALIGN(0x1000);
  .tohost : {
    *(.tohost)
  }

  . = ALIGN(0x1000);
  .text : {
    *(.text)
  }

  .data : {
    *(.data)
  }

  .sdata : {
    __global_pointer$ = . + 0x800;
    *(.srodata*)
    *(.sdata*)
  }

  .bss : {
    *(.bss)
  }

  _end = .;
}
