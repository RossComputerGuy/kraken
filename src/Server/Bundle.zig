const std = @import("std");
const build_options = @import("options");
const Server = @import("../Server.zig");
const Bundle = @This();

pub const Data = union(enum) {
    raw: []const u8,
    file: std.fs.File,

    pub fn init(options: Server.Options) !Data {
        if (options.bundle) |bundle_path| {
            return .{
                .file = try std.fs.openFileAbsolute(bundle_path, .{}),
            };
        }

        if (build_options.bundle) {
            return .{
                .raw = @import("bundle").frontend,
            };
        }

        return .{
            .file = try std.fs.openFileAbsolute(build_options.libdir ++ std.fs.path.sep_str ++ "frontend.tar.gz", .{}),
        };
    }

    pub fn deinit(self: Data) void {
        return switch (self) {
            .file => |file| file.close(),
            else => {},
        };
    }
};

data: Data,
buffer: std.ArrayList(u8),

pub fn init(gpa: std.mem.Allocator, options: Server.Options) !Bundle {
    return .{
        .data = try Data.init(options),
        .buffer = std.ArrayList(u8).init(gpa),
    };
}

pub fn deinit(self: *Bundle) void {
    self.data.deinit();
    self.buffer.deinit();
}

pub fn ensureReadable(self: *Bundle) !void {
    if (self.buffer.items.len == 0) {
        switch (self.data) {
            .file => |file| try std.compress.gzip.decompress(file.reader(), self.buffer.writer()),
            .raw => |raw| {
                var fbs = std.io.fixedBufferStream(raw);
                try std.compress.gzip.decompress(fbs.reader(), self.buffer.writer());
            },
        }
    }
}

pub fn readFile(self: *Bundle, path: []const u8) ![]const u8 {
    try self.ensureReadable();

    var fbs = std.io.fixedBufferStream(self.buffer.items);

    var file_name_buffer = [_]u8{0} ** std.fs.max_path_bytes;
    var link_name_buffer = [_]u8{0} ** std.fs.max_path_bytes;

    var iter = std.tar.iterator(fbs.reader(), .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });

    while (try iter.next()) |entry| {
        if (std.mem.eql(u8, entry.name[1..], path)) {
            if (entry.kind == .directory) return error.IsDir;
            return try entry.reader().readAllAlloc(self.buffer.allocator, std.math.maxInt(usize));
        }
    }
    return error.FileNotFound;
}
