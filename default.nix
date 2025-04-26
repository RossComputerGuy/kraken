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

  nativeBuildInputs = with pkgs; [
    zig
    zig.hook
    bun
  ];

  postUnpack = ''
    ln -s ${pkgs.runCommand "${finalAttrs.pname}-zig-deps-${finalAttrs.version}" {
      inherit (finalAttrs) src;

      nativeBuildInputs = [ pkgs.zig ];

      outputHashAlgo = null;
      outputHashMode = "recursive";
      outputHash = "sha256-jdbmy2z12/jFmmOJE8WuBe9ktSEMYXDdxhcvlwUewQA=";
    } ''
      export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)

      runPhase unpackPhase

      zig build --fetch

      mv $ZIG_GLOBAL_CACHE_DIR/p $out
    ''} $ZIG_GLOBAL_CACHE_DIR/p
  '';

  doCheck = true;
  nativeCheckInputs = with pkgs; [
    wasmtime
  ];

  zigCheckFlags = "-fwasmtime";
})
