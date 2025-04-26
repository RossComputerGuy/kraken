const std = @import("std");

pub const Machine = extern struct {
    extern fn nix_store_machine_parse_config(
        default_systems: [*]const [:0]const u8,
        n_default_systems: usize,
        config: [*]const u8,
        config_len: usize,
        out_len: *usize,
    ) ?[*]const *const Machine;

    pub fn parseConfig(alloc: std.mem.Allocator, default_systems: []const [:0]const u8, config: []const u8) !std.ArrayList(*const Machine) {
        var n_slice: usize = 0;
        const slice = nix_store_machine_parse_config(default_systems.ptr, default_systems.len, config.ptr, config.len, &n_slice) orelse return error.OutOfMemory;

        var machines = try std.ArrayList(*const Machine).initCapacity(alloc, n_slice);
        errdefer machines.deinit();

        machines.appendSliceAssumeCapacity(slice[0..n_slice]);
        return machines;
    }

    test "Parse config" {
        const machines = try parseConfig(std.testing.allocator, &.{},
            \\ssh://mac x86_64-darwin
            \\ssh://beastie x86_64-freebsd
        );
        defer machines.deinit();
        std.debug.print("{any}\n", .{machines.items});
    }
};

test {
    _ = Machine;
}
