{
  lib,
  stdenv,
  libcxxStdenv,
  gtest,
  rapidcheck,
  aws-sdk-cpp,
  aws-crt-cpp,
  runCommand,
  importNpmLock,
  zig,
  bun,
  nodejs,
  pkg-config,
  wasmtime,
  nix,
  bundle ? null,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "kraken";
  version = "0.1.0";

  src = ../.;
  zigZon = ../build.zig.zon;
  packageLockJSON = ../package-lock.json;

  npmDeps = importNpmLock {
    npmRoot = finalAttrs.src;
  };

  nativeBuildInputs = [
    zig
    zig.hook
    bun
    nodejs
    importNpmLock.npmConfigHook
    pkg-config
  ];

  buildInputs = [
    (nix.override {
      stdenv = libcxxStdenv;
      rapidcheck = rapidcheck.override {
        stdenv = libcxxStdenv;
      };
      gtest = gtest.override {
        stdenv = libcxxStdenv;
      };
      aws-sdk-cpp = aws-sdk-cpp.override {
        stdenv = libcxxStdenv;
        aws-crt-cpp = aws-crt-cpp.override {
          stdenv = libcxxStdenv;
        };
      };
    })
  ];

  postUnpack = ''
    ln -s ${
      let
        suffix = "-${(lib.removeSuffix "-build.zig.zon" (lib.removePrefix "${builtins.storeDir}/" finalAttrs.zigZon))}";
      in
      runCommand "${finalAttrs.pname}-zig-deps-${finalAttrs.version}${suffix}"
        {
          inherit (finalAttrs) src;

          nativeBuildInputs = [ zig ];

          outputHashAlgo = null;
          outputHashMode = "recursive";
          outputHash = "sha256-vqVLKTjjYqaw7Gi3SnbIJ3t4U8TMQ8nTEd/CLRIRhME=";
        }
        ''
          export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)

          runPhase unpackPhase

          zig build --fetch

          mv $ZIG_GLOBAL_CACHE_DIR/p $out
        ''
    } $ZIG_GLOBAL_CACHE_DIR/p
  '';

  zigBuildFlags = lib.concatStringsSep " " (
    [
      "-Dlocked-npm-modules"
    ]
    ++ lib.optional (bundle != null) "-Dbundle=${lib.boolToString bundle}"
  );

  doCheck = true;
  nativeCheckInputs = [
    wasmtime
  ];

  zigCheckFlags = "-fwasmtime";
})
