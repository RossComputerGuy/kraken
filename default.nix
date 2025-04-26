{
  system ? builtins.currentSystem,
  pkgs ?
    import
      (builtins.fetchTree (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked)
      .outPath
      { inherit system; },
}:
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "kraken";
  version = "0.1.0";

  src = ./.;
  zigZon = ./build.zig.zon;
  packageLockJSON = ./package-lock.json;

  npmDeps = pkgs.importNpmLock {
    npmRoot = ./.;
  };

  nativeBuildInputs = with pkgs; [
    zig
    zig.hook
    bun
    nodejs
    importNpmLock.npmConfigHook
  ];

  postUnpack = ''
    ln -s ${
      let
        suffix = "-${(pkgs.lib.removeSuffix "-build.zig.zon" (pkgs.lib.removePrefix "${builtins.storeDir}/" finalAttrs.zigZon))}";
      in
      pkgs.runCommand "${finalAttrs.pname}-zig-deps-${finalAttrs.version}${suffix}"
        {
          inherit (finalAttrs) src;

          nativeBuildInputs = [ pkgs.zig ];

          outputHashAlgo = null;
          outputHashMode = "recursive";
          outputHash = "sha256-te+VtPT7P0tC75HZjK/RYsM9f2Tx0lWwG4UcPjpAiMQ=";
        }
        ''
          export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)

          runPhase unpackPhase

          zig build --fetch

          mv $ZIG_GLOBAL_CACHE_DIR/p $out
        ''
    } $ZIG_GLOBAL_CACHE_DIR/p
  '';

  zigBuildFlags = "-Dlocked-npm-modules";

  doCheck = true;
  nativeCheckInputs = with pkgs; [
    wasmtime
  ];

  zigCheckFlags = "-fwasmtime";
})
