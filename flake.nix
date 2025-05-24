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

    genAttrs = prefix: names: f:
      builtins.listToAttrs (builtins.map (name: {
          name = "${prefix}-${name}";
          value = f name;
        })
        names);
    languages = ["en" "es"];
    inherit (nixpkgs.lib) toUpper;
    translations = builtins.listToAttrs (builtins.map (lang: {
        name = "translation-${lang}";
        value = (
          let
            pkgs = import nixpkgs {system = "x86_64-linux";};
          in
            pkgs.stdenv.mkDerivation {
              name = "iron-os-translation-${lang}";
              src = "${src}/Translations";
              buildPhase = let
                langUp = toUpper lang;
              in ''
                mkdir build
                python3 make_translation.py -o Translation.${langUp}.cpp --output-pickled ${langUp}.pickle ${langUp}
              '';
              installPhase = ''
                mkdir -p $out
                cp ./Translation.*.cpp $out
                cp ./*.pickle $out
              '';
              prePatch = ''
                substituteInPlace make_translation.py --replace ' = read_version()' ' = "v2.19"'
              '';
              buildInputs = [
                (pkgs.python3.withPackages (ps: [
                  (ps.buildPythonPackage {
                    pname = "bdflib";
                    version = "2.0.1";
                    src = py_bdflib;
                    doCheck = false;
                  })
                ]))
              ];
            }
        );
      })
      languages);
    builds = genAttrs "ironos" languages (
      lang: let
        cross =
          (import nixpkgs {
            system = "x86_64-linux";
            overlays = [self.overlays.default];
          })
          .pkgsCross
          .riscv32-embedded-temp;
        translation = builtins.getAttr "translation-${lang}" translations;
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
          name = "ironos-${lang}";
          src = "${src}/source";
          prePatch = ''
            substituteInPlace Makefile --replace 'riscv-' 'riscv32-'
            substituteInPlace Makefile --replace 'LIBS=' 'LIBS=-L${newlib}'
            substituteInPlace Makefile --replace '$(HEXFILE_DIR)/$(model)_%.dfu' ' '
            cp -r ${usbpd}/* ./Core/Drivers/usb-pd
          '';
          buildFlags = ["firmware-${toUpper lang}"];
          configurePhase = ''
            mkdir -p Core/Gen/translation.files
            cp ${translation}/Translation.*.cpp Core/Gen
            cp ${translation}/*.pickle Core/Gen/translation.files
          '';
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
        inherit (pkgs) hello;
        default = self.packages.${system}.ironos-en;
      }
      // builds
      // translations);
    overlays.default = final: prev: {
      pkgsCross.riscv32-embedded-temp = import prev.path {
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
  };
}
