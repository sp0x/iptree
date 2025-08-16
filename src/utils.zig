const std = @import("std");
const fs = std.fs;
const math = std.math;
const net = std.net;
const mem = std.mem;

pub fn ip_fmt(addr: std.net.Address, out_stream: anytype) !void {
    switch (addr.any.family) {
        std.posix.AF.INET => |_| {
            const ip_b = @as(*const [4]u8, @ptrCast(&addr.in.sa.addr));
            try out_stream.print("{d}.{d}.{d}.{d}", .{
                ip_b[0],
                ip_b[1],
                ip_b[2],
                ip_b[3],
            });
        },
        std.posix.AF.INET6 => |_| {
            const ip_b = addr.in6.sa.addr;
            try out_stream.print("{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}", .{
                ip_b[0],
                ip_b[1],
                ip_b[2],
                ip_b[3],
                ip_b[4],
                ip_b[5],
                ip_b[6],
                ip_b[7],
            });
        },
        else => |_| {
            unreachable; // Unsupported address family    },
            //
        },
    }
}

pub fn days_since_modification(dataset_dir: fs.Dir, descriptor: []const u8) !u64 {
    const modification_tsec = try last_modified(dataset_dir, descriptor);
    const now = std.time.timestamp();
    const delta_ms: i128 = now - modification_tsec;
    // The modification date MUST be in the past
    std.debug.assert(delta_ms >= 0);
    const days = @divTrunc(delta_ms, std.time.ns_per_day);
    return @bitCast(math.lossyCast(i64, days));
}

pub fn assert(ok: bool, comptime message: []const u8, args: anytype) void {
    if (!ok) {
        // assertion failure
        if (std.debug.runtime_safety) {
            std.debug.panicExtra(@returnAddress(), message, args);
        } else {
            unreachable;
        }
    }
}

pub fn last_modified(dataset_dir: fs.Dir, descriptor: []const u8) !i64 {
    const ipv4_data_file = dataset_dir.openFile(descriptor, .{ .mode = .read_only }) catch |err| {
        if (err == error.FileNotFound) {
            return 0;
        }
        return err;
    };
    defer ipv4_data_file.close();
    const ipv4_meta = try ipv4_data_file.metadata();
    const ipv4_ts_nano = ipv4_meta.modified();

    return math.lossyCast(i64, @divTrunc(ipv4_ts_nano, std.time.ns_per_s));
}

test "utils" {
    const out_stream = std.io.getStdOut().writer();
    const addr_v4 = try net.Address.parseIp4("192.168.1.1", 0);
    const addr_v6 = try net.Address.parseIp6("2001:0db8:85a3:0000:0000:8a2e:0370:7334", 0);

    try ip_fmt(addr_v4, out_stream);
    try out_stream.writeAll("\n");

    try ip_fmt(addr_v6, out_stream);
    try out_stream.writeAll("\n");
}
