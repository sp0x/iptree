const std = @import("std");
const expect = std.testing.expect;
const fs = std.fs;
const math = std.math;
const net = std.net;
const mem = std.mem;
const print = std.debug.print;
const exec = @import("process.zig").exec;

pub fn trim_quotes(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') {
        return s[1 .. s.len - 1];
    }
    if (s.len >= 1 and s[0] == '"') {
        return s[1..];
    }
    if (s.len >= 1 and s[s.len - 1] == '"') {
        return s[0 .. s.len - 1];
    }
    return s;
}
/// Formats an IP address into a human-readable string.
/// This function takes a network address and writes the formatted IP address
/// to the provided output stream. It supports both IPv4 and IPv6 addresses.
////// # Parameters
/// - `addr`: The network address to format.
/// - `out_stream`: The output stream where the formatted IP address will be written.
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
            const ip_bytes = addr.in6.sa.addr;
            try out_stream.print("{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}", .{ ip_bytes[0], ip_bytes[1], ip_bytes[2], ip_bytes[3], ip_bytes[4], ip_bytes[5], ip_bytes[6], ip_bytes[7], ip_bytes[8], ip_bytes[9], ip_bytes[10], ip_bytes[11], ip_bytes[12], ip_bytes[13], ip_bytes[14], ip_bytes[15] });
        },
        else => |_| {
            unreachable; // Unsupported address family    },
            //
        },
    }
}

pub fn days_since_modification(dataset_dir: fs.Dir, descriptor: []const u8) !u64 {
    const modification_tsec = try last_modified(dataset_dir, descriptor);
    const now_sec = std.time.timestamp();
    const delta_sec: i128 = now_sec - modification_tsec;
    // The modification date MUST be in the past
    std.debug.assert(delta_sec >= 0);
    const days = @divTrunc(delta_sec, std.time.s_per_day);
    return @bitCast(math.lossyCast(i64, days));
}

pub fn ipv4_to_u32(addr: std.net.Address) u32 {
    const bytes = std.mem.asBytes(&addr.in.sa.addr);
    return std.mem.readInt(u32, bytes, .big);
}

// Converts an IP address into bytes slice, e.g., IPv6 address 1000:0ac3:22a2:0000:0000:4b3c:0504:1234
// is converted into [16 0 10 195 34 162 0 0 0 0 75 60 5 4 18 52].
pub fn ip_to_bytes(address: *const std.net.Address) []const u8 {
    return switch (address.any.family) {
        std.posix.AF.INET => {
            return std.mem.asBytes(&address.in.sa.addr);
        },
        std.posix.AF.INET6 => &address.in6.sa.addr,
        else => unreachable,
    };
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

/// Gets the last modified time **in seconds** of a file descriptor.
pub fn last_modified(dataset_dir: fs.Dir, descriptor: []const u8) !i64 {
    const ipv4_data_file = try dataset_dir.openFile(descriptor, .{ .mode = .read_only });
    defer ipv4_data_file.close();
    const ipv4_meta = try ipv4_data_file.metadata();
    const ipv4_ts_nano = ipv4_meta.modified();

    return math.lossyCast(i64, @divTrunc(ipv4_ts_nano, std.time.ns_per_s));
}

test "utils" {
    var buff: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buff);
    const writer = stream.writer();
    const addr_v4 = try net.Address.parseIp4("192.168.1.1", 0);
    const addr_v6 = try net.Address.parseIp6("2001:0db8:85a3:0000:0000:8a2e:0370:7334", 0);
    try ip_fmt(addr_v4, writer);
    try writer.writeAll("\n");

    try ip_fmt(addr_v6, writer);
    try writer.writeAll("\n");

    // Assert that the IPs are formatted correctly in the buffer
    const formatted = stream.getWritten();
    const expected_v4 = "192.168.1.1";
    const expected_v6 = "2001:0db8:85a3:0000:0000:8a2e:0370:7334";
    try expect(mem.indexOf(u8, formatted, expected_v4) != null);
    try expect(mem.indexOf(u8, formatted, expected_v6) != null);
}

pub fn exec_fetch(script: []const u8, base_dir: []const u8) !void {
    // Implement fetching logic if needed
    const allocator = std.heap.page_allocator;
    var build_args = std.ArrayList([]const u8).init(allocator);
    defer build_args.deinit();
    try build_args.appendSlice(&[_][]const u8{ script, base_dir });

    const res = try exec(null, build_args.items, allocator);
    if (res.Exited != 0) {
        return error.NotImplemented; // Or handle the error as needed
    }
}
