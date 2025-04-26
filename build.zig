const std = @import("std");

fn gitHash(b: *std.Build) ?[]const u8 {
    const git = b.findProgram(&.{"git"}, &.{}) catch return null;

    var e: u8 = 0;
    const result = b.runAllowFail(&.{
        git,
        "rev-parse",
        "HEAD",
    }, &e, .Inherit) catch return null;
    return result[0..(std.mem.indexOf(u8, result, "\n") orelse unreachable)];
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bundle = b.option(bool, "bundle", "Whether to bundle the frontend into the server") orelse (optimize == .ReleaseFast);
    const locked_npm_modules = b.option(bool, "locked-npm-modules", "Whether to copy the node_modules directory or npm install") orelse false;

    const bun = b.findProgram(&.{"bun"}, &.{}) catch @panic("Cannot find bun");
    const npm = b.findProgram(&.{"npm"}, &.{}) catch @panic("Cannot find npm");
    const tar = b.findProgram(&.{"tar"}, &.{}) catch @panic("Cannot find tar");

    const build_zon = std.zon.parse.fromSlice(struct {
        version: []const u8,
    }, b.allocator, @embedFile("build.zig.zon"), null, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        std.debug.panic("Failed to parse build.zig.zon: {s}", .{@errorName(err)});
    };

    var version = std.SemanticVersion.parse(build_zon.version) catch |err| {
        std.debug.panic("Failed to parse version in build.zig.zon: {s}", .{@errorName(err)});
    };

    if (gitHash(b)) |hash| {
        version.build = hash[0..7];
    }

    const options_client = b.addOptions();
    options_client.addOption(std.SemanticVersion, "version", version);

    const exe_client = b.addExecutable(.{
        .name = "kraken",
        .optimize = optimize,
        .root_module = b.createModule(.{
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .wasi,
                .ofmt = .wasm,
            }),
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{
                    .name = "options",
                    .module = options_client.createModule(),
                },
            },
        }),
    });

    exe_client.export_memory = true;

    const frontend_source = b.addWriteFiles();
    _ = frontend_source.addCopyFile(b.path("index.ts"), "index.ts");
    _ = frontend_source.addCopyFile(b.path("package.json"), "package.json");
    _ = frontend_source.addCopyFile(b.path("package-lock.json"), "package-lock.json");
    _ = frontend_source.addCopyFile(exe_client.getEmittedBin(), "client.wasm");

    const frontend_source_index_html = frontend_source.addCopyFile(b.path("index.html"), "index.html");

    const build_frontend = b.addSystemCommand(&.{
        bun,
        "build",
        "--minify",
        "--target=browser",
    });

    if (locked_npm_modules) {
        _ = frontend_source.addCopyDirectory(b.path("node_modules"), "node_modules", .{});
    } else {
        const package_lock = b.addSystemCommand(&.{
            npm,
            "install",
        });

        package_lock.setCwd(frontend_source.getDirectory());

        build_frontend.step.dependOn(&package_lock.step);
    }

    const frontend_build = build_frontend.addPrefixedOutputDirectoryArg("--outdir=", ".");

    build_frontend.addFileArg(frontend_source_index_html);

    const frontend_tar = b.addSystemCommand(&.{
        tar,
        "czf",
    });

    frontend_tar.setCwd(frontend_build);
    const out_frontend_tar = frontend_tar.addOutputFileArg("frontend.tar.gz");
    frontend_tar.addArg(".");

    const options_server = b.addOptions();
    options_server.addOption(bool, "bundle", bundle);
    options_server.addOption([]const u8, "libdir", b.getInstallPath(.lib, "kraken"));
    options_server.addOption(std.SemanticVersion, "version", version);

    const libnix = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("lib/nix.zig"),
        .link_libc = true,
        .link_libcpp = true,
    });

    libnix.linkSystemLibrary("nix-store", .{});

    libnix.addCSourceFiles(.{
        .root = b.path("lib/nix"),
        .files = &.{
            "store/machines.cpp",
        },
        .flags = &.{
            "-std=c++2a",
        },
    });

    const module_server = b.createModule(.{
        .target = target,
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{
                .name = "options",
                .module = options_server.createModule(),
            },
            .{
                .name = "xev",
                .module = b.dependency("libxev", .{
                    .target = target,
                    .optimize = optimize,
                }).module("xev"),
            },
            .{
                .name = "nix",
                .module = libnix,
            },
        },
    });

    if (bundle) {
        const bundle_module_source = b.addWriteFiles();
        _ = bundle_module_source.addCopyFile(out_frontend_tar, "frontend.tar.gz");

        const bundle_module_source_root = bundle_module_source.add("bundle.zig", "pub const frontend = @embedFile(\"frontend.tar.gz\");");

        const bundle_module = b.createModule(.{
            .root_source_file = bundle_module_source_root,
        });
        module_server.addImport("bundle", bundle_module);
    } else {
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(out_frontend_tar, .lib, "kraken/frontend.tar.gz").step);
    }

    const exe_server = b.addExecutable(.{
        .name = "kraken",
        .optimize = optimize,
        .root_module = module_server,
    });

    b.installArtifact(exe_server);

    const step_test = b.step("test", "Run all tests");

    const test_client = b.addTest(.{
        .name = "test-client",
        .root_module = exe_client.root_module,
    });

    if (b.enable_wasmtime) {
        const test_client_run = b.addRunArtifact(test_client);
        step_test.dependOn(&test_client_run.step);
    }

    const test_bun = b.addSystemCommand(&.{
        bun,
        "test",
    });

    step_test.dependOn(&test_bun.step);

    const test_nix = b.addTest(.{
        .name = "test-nix",
        .root_module = libnix,
    });

    test_nix.linkSystemLibrary("nix-store");

    const test_nix_run = b.addRunArtifact(test_nix);
    step_test.dependOn(&test_nix_run.step);

    const test_server = b.addTest(.{
        .name = "test-server",
        .root_module = exe_server.root_module,
    });

    const test_server_run = b.addRunArtifact(test_server);
    step_test.dependOn(&test_server_run.step);

    const step_run = b.step("run", "Run Kraken");
    const exe_server_run = b.addRunArtifact(exe_server);
    exe_server_run.addPrefixedFileArg("--bundle=", out_frontend_tar);
    step_run.dependOn(&exe_server_run.step);
}
