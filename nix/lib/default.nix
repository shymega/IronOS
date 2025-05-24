{
  inputs,
  pkgs ? inputs.nixpkgs.legacyPackages.x86_64-linux,
  lib ? pkgs.lib,
}: {
  inherit (lib) toUpper;
}
