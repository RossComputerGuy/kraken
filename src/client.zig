const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main(_: Allocator) !void {
    std.debug.print("Hello world!\n", .{});
}
