(builtins.fetchTree (builtins.fromJSON (builtins.readFile ../flake.lock)).nodes.nixpkgs.locked)
.outPath
