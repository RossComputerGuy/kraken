{
  system ? builtins.currentSystem,
  pkgs ? import (import ./nix/nixpkgs.nix) { inherit system; },
}:
pkgs.callPackage ./nix/package.nix { }
