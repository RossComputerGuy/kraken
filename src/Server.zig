const std = @import("std");
const Allocator = std.mem.Allocator;
const build_options = @import("options");
const xev = @import("xev");
const Server = @This();

pub const Bundle = @import("Server/Bundle.zig");

pub const Options = struct {
    port: u16 = 8080,
    address: []const u8 = "0.0.0.0",
    bundle: ?[]const u8 = null,
};

gpa: Allocator,
server: std.net.Server,
loop: xev.Loop,
completion_server_accept: xev.Completion,
bundle: Bundle,

pub fn create(gpa: Allocator, options: Options) !*Server {
    var self = try gpa.create(Server);
    errdefer gpa.destroy(self);

    self.gpa = gpa;

    const addr = std.net.Address.resolveIp(options.address, options.port) catch |err| {
        std.debug.panic("Failed to resolve \"{s}:{}\": {}", .{ options.address, options.port, err });
    };

    self.server = addr.listen(.{
        .force_nonblocking = true,
    }) catch |err| {
        std.debug.panic("Failed to listen on \"{}\": {}", .{ addr, err });
    };
    errdefer self.server.deinit();

    self.bundle = try Bundle.init(gpa, options);
    errdefer self.bundle.deinit();

    self.loop = try xev.Loop.init(.{});
    errdefer self.loop.deinit();

    self.completion_server_accept = xev.Completion{
        .op = .{
            .accept = .{
                .socket = self.server.stream.handle,
            },
        },
        .userdata = null,
        .callback = (struct {
            fn func(
                _: ?*anyopaque,
                _: *xev.Loop,
                c: *xev.Completion,
                r: xev.Result,
            ) xev.CallbackAction {
                const server: *Server = @fieldParentPtr("completion_server_accept", c);
                if (r.accept catch null) |conn_fd| {
                    server.accept(.{
                        .stream = .{ .handle = conn_fd },
                        .address = .{
                            .any = c.op.accept.addr,
                        },
                    }) catch |err| std.log.warn("Failed to handle connection {}: {}", .{ conn_fd, err });
                }
                return .rearm;
            }
        }).func,
    };
    self.loop.add(&self.completion_server_accept);

    std.log.info("Server is up at http://{}", .{addr});
    return self;
}

pub fn destroy(self: *Server) void {
    self.loop.deinit();
    self.server.deinit();
    self.bundle.deinit();
    self.gpa.destroy(self);
}

pub fn accept(self: *Server, conn: std.net.Server.Connection) !void {
    var buffer: [1024]u8 = undefined;
    var http = std.http.Server.init(conn, &buffer);

    var req = try http.receiveHead();

    const path = if (std.mem.eql(u8, req.head.target, "/")) "/index.html" else req.head.target;
    var options = std.http.Server.Request.RespondOptions{
        .keep_alive = false,
    };

    var headers = std.ArrayList(std.http.Header).init(self.gpa);
    defer headers.deinit();

    const source = self.bundle.readFile(path) catch |err| blk: {
        if (err == error.FileNotFound) {
            options.status = .not_found;
        } else {
            options.status = .bad_request;
        }

        var output = std.ArrayList(u8).init(self.gpa);
        defer output.deinit();

        output.writer().print("Failed to read file \"{s}\": {}\n", .{ path, err }) catch @panic("OOM");

        if (@errorReturnTrace()) |et| {
            std.debug.writeStackTrace(
                et.*,
                output.writer(),
                std.debug.getSelfDebugInfo() catch @panic("Failed to get debug info"),
                .no_color,
            ) catch @panic("OOM");
        }

        break :blk output.toOwnedSlice() catch @panic("OOM");
    };
    defer self.gpa.free(source);

    const ext = std.fs.path.extension(path);
    if (std.mem.eql(u8, ext, ".js")) {
        try headers.append(.{
            .name = "content-type",
            .value = "text/javascript",
        });
    } else if (std.mem.eql(u8, ext, ".html")) {
        try headers.append(.{
            .name = "content-type",
            .value = "text/html",
        });
    } else if (std.mem.eql(u8, ext, ".wasm")) {
        try headers.append(.{
            .name = "content-type",
            .value = "application/wasm",
        });
    }

    options.extra_headers = headers.items;
    try req.respond(source, options);
}

fn parseArgValue(args: *std.process.ArgIterator, arg: []const u8) struct { []const u8, ?[]const u8 } {
    if (std.mem.indexOf(u8, arg, "=")) |i| {
        return .{ arg[0..i], arg[(i + 1)..] };
    }
    return .{
        arg,
        args.next(),
    };
}

pub fn main(gpa: Allocator) !void {
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();

    const argv0 = args.next() orelse "kraken";

    var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer stdout.flush() catch |err| std.debug.panic("Failed to flush stdout: {}", .{err});

    var options: Options = .{};

    while (args.next()) |arg_name| {
        if (std.mem.eql(u8, arg_name, "--help") or std.mem.eql(u8, arg_name, "-h")) {
            try stdout.writer().print(
                \\Kraken CI Server
                \\
                \\Usage: {s} [options...]
                \\
                \\Options:
                \\  --help, -h     Prints all available options.
                \\  --port, -p     Sets the port to listen on (default: 8080).
                \\  --address, -a  Sets the address to listen on (default: 0.0.0.0).
                \\  --bundle, -b   Sets the path to the frontend bundle.
                \\  --version, -v  Prints the version.
                \\
            , .{
                argv0,
            });
            return;
        } else if (std.mem.eql(u8, arg_name, "--version") or std.mem.eql(u8, arg_name, "-v")) {
            try stdout.writer().print("Kraken CI Server v{}\n", .{build_options.version});
        } else {
            const arg = parseArgValue(&args, arg_name);
            if (std.mem.eql(u8, arg[0], "--port") or std.mem.eql(u8, arg[0], "-p")) {
                options.port = std.fmt.parseInt(
                    u16,
                    arg[1] orelse std.debug.panic("Argument \"{s}\" is missing value", .{arg[0]}),
                    10,
                ) catch |err| std.debug.panic("Argument \"{s}\" has an invalid integer: {}", .{
                    arg[0],
                    err,
                });
            } else if (std.mem.eql(u8, arg[0], "--address") or std.mem.eql(u8, arg[0], "-a")) {
                options.address = arg[1] orelse std.debug.panic("Argument \"{s}\" is missing value", .{arg[0]});
            } else if (std.mem.eql(u8, arg[0], "--bundle") or std.mem.eql(u8, arg[0], "-b")) {
                options.bundle = arg[1] orelse std.debug.panic("Argument \"{s}\" is missing value", .{arg[0]});
            } else {
                std.debug.panic("Unknown argument \"{s}\"", .{arg[0]});
            }
        }
    }

    const server = try create(gpa, options);
    defer server.destroy();

    try server.loop.run(.until_done);
}
