# Kraken CI

A modern CI service for Nix.

## Building

### With Nix

Just build with nix using either `nix-build` or `nix build`. You can even get fancy with [`nom`](https://code.maralorn.de/maralorn/nix-output-monitor) and do `nom build` or `nom-build`.

### Without Nix / development

For development, it is recommended to use the `nix develop` command to enter the dev shell. From there, run `unset ZIG_GLOBAL_CACHE_DIR` in order to not get any permission errors. You can then build with `zig build`, it is recommended to look at `zig build --help` for all build options.

#### No Nix at all

The following dependencies are required:

- `bun` (recommended version: 0.2.10)
- `npm` (recommended version: 10.9.2)
- `zig` (recommended version: 0.14)
- GNU tar

Build instructions are the same as the development section.
