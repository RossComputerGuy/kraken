const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main(_: Allocator) !void {
    var html = std.fs.File{ .handle = 3 };
    try html.writer().print("Hello world!\n", .{});
}
