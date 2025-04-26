const builtin = @import("builtin");
const std = @import("std");
const native_os = builtin.target.os.tag;

const client = @import("client.zig");
const Server = @import("Server.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        if (native_os == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    if (native_os == .wasi) {
        try client.main(gpa);
    } else {
        try Server.main(gpa);
    }
}

test {
    if (native_os == .wasi) {
        _ = client;
    } else {
        _ = Server;
    }
}
