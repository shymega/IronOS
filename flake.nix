{
  description = "Open Source Soldering Iron firmware for Miniware and Pinecil";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
    meta = {
      url = "github:Ralim/IronOS-Meta?ref=v2022.02.24";
      flake = false;
    };
    usbpd = {
      url = "github:Ralim/usb-pd?rev=b38598261df4f705bcbd37cdd5dcccfaa5ab7b4a";
      flake = false;
    };
    py_bdflib = {
      url = "gitlab:Screwtapello/bdflib?ref=v2.0.1";
      flake = false;
    };
  };
  outputs = inputs: let
    inherit (inputs) self nixpkgs meta usbpd py_bdflib;
    src = "${self}";
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forSystems = systems: f:
      inputs.nixpkgs.lib.genAttrs systems
      (system: f system inputs.nixpkgs.legacyPackages.${system});
    forAllSystems = forSystems supportedSystems;

    genAttrs = prefix: f: let
      inherit (nixpkgs.lib) flatten map;
      inherit (builtins) listToAttrs;
    in
      listToAttrs (flatten (
        map (
          model:
            map (lang: {
              name = "${prefix}-${model}-${lang}";
              value = f model lang;
            })
            languages
        )
        models
      ));
    languages = import "${self}/nix/utils/translations-list.nix";
    models = import "${self}/nix/utils/models-list.nix";
    builds = genAttrs "ironos" (
      model: lang: let
        cross = let
          riscv-overlay = final: prev: {
            pkgsCross.riscv32-embedded-ilp32 = import prev.path {
              crossSystem = {
                config = "riscv32-none-elf";
                libc = "newlib";
                gcc = {
                  arch = "rv32i";
                  abi = "ilp32";
                };
              };
              system = "x86_64-linux";
            };
          };
        in
          (import nixpkgs {
            system = "x86_64-linux";
            overlays = [riscv-overlay];
          })
          .pkgsCross
          .riscv32-embedded-ilp32;
        newlib = cross.stdenv.mkDerivation {
          name = "newlib";
          src = cross.newlib-nano.overrideAttrs (_: oldAttrs: {
            configureFlags = oldAttrs.configureFlags ++ ["--disable-float"];
          });
          dontBuild = true;
          installPhase = ''
            mkdir -p $out
            cp riscv32-none-elf/lib/libc.a $out/libc_nano.a
            cp riscv32-none-elf/lib/libm.a $out/libm_nano.a
            cp riscv32-none-elf/lib/libg.a $out/libg_nano.a
          '';
        };
      in
        cross.stdenv.mkDerivation {
          name = "ironos-${model}-${lang}";
          src = "${src}/source";
          prePatch = ''
            substituteInPlace Makefile --replace 'riscv-' 'riscv32-'
            substituteInPlace Makefile --replace 'LIBS=' 'LIBS=-L${newlib}'
            substituteInPlace Makefile --replace '$(HEXFILE_DIR)/$(model)_%.dfu' ' '
            cp -r ${usbpd}/* ./Core/Drivers/usb-pd
          '';
          buildFlags = ["model=${model}" "firmware-${lang}"];
          installPhase = ''
            mkdir $out
            cp Hexfile/*.hex $out
            cp Hexfile/*.bin $out
          '';
        }
    );
  in {
    packages = forAllSystems (system: pkgs: let
      lib = pkgs.lib.extend (
        _: prev: {
          lib = prev.lib // import ./nix/lib {inherit inputs pkgs lib;};
        }
      );
    in
      {
        default = self.packages.${system}.ironos-Pinecilv2-EN;
      }
      // builds);
  };
}
