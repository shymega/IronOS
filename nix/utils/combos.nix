rec {
  TS100 = {
    crossSystem = {
      config = "arm-none-eabi";
      libc = "newlib";
    };
  };
  TS80 = TS100;
  TS80P = TS100;
  Pinecil = {
    compiler = "riscv32-embedded-ilp32";
    crossSystem = {
      config = "riscv32-none-elf";
      libc = "newlib";
      gcc = {
        arch = "rv32i";
        abi = "ilp32";
      };
    };
  };
  MHP30 = TS100;
  Pinecilv2 = Pinecil;
  S60 = TS100;
  S60P = TS100;
  T55 = TS100;
  TS101 = TS100;
}
