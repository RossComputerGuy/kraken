{
  description = "Kraken CI for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    systems.url = "github:nix-systems/default";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      perSystem =
        {
          self',
          inputs,
          lib,
          pkgs,
          ...
        }:
        {
          packages = {
            default = (pkgs.callPackage ./nix/package.nix { }).overrideAttrs (
              f: p: {
                version = "0.1.0-git+${self.shortRev or "dirty"}";
              }
            );
            bundled = self'.packages.default.override {
              bundle = true;
            };
          };
        };
    };
}
