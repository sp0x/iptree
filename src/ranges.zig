const std = @import("std");
const posix = std.posix;
const net = @import("std").net;
const mem = std.mem;
const math = std.math;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Ip4Address = net.Ip4Address;
const Address = net.Address;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const Errors = error{
    InvalidFamily,
    InvalidAddress,
    InvalidCIDR,
};

pub const NetworkAndCidr = struct {
    network: net.Ip4Address,
    cidr: u8,

    pub fn format(
        self: *const NetworkAndCidr,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        if (fmt.len != 0) std.fmt.invalidFmtError(fmt, self);
        _ = options;

        try out_stream.print("{}/{d}", .{ self.network, self.cidr });
    }
};

pub fn GetFamily(ipAddress: []const u8) u8 {
    if (mem.containsAtLeast(u8, ipAddress, 1, ":")) {
        return posix.AF.INET6;
    } else {
        return posix.AF.INET;
    }
}

fn asNumber(addr: Address) !u32 {
    if (addr.family == posix.AF.INET) {
        return mem.readInt(u32, mem.asBytes(&addr.addr), .big);
    } else if (addr.family == posix.AF.INET6) {
        return mem.readInt(u32, mem.asBytes(&addr.addr), .little);
    } else {
        return Errors.InvalidFamily;
    }
}

pub fn ipv4AsNumber(addr: Ip4Address) u32 {
    return mem.readInt(u32, mem.asBytes(&addr.sa.addr), .big);
}

fn ip4(str: []const u8) !Ip4Address {
    const ip = try Ip4Address.parse(str, 0);
    return ip;
}

fn ip4str(alloc: Allocator, ip: Ip4Address) ![]const u8 {
    // Convert the IP address to a string representatio
    const str = try std.fmt.allocPrint(alloc, "{}", .{ip});
    // Remove the trailing :0
    return str[0 .. str.len - 2];
}

pub fn GetCIDRsInRange(alloc: Allocator, start_ip: Ip4Address, end_ip: Ip4Address) !ArrayList(NetworkAndCidr) {
    var results = std.ArrayList(NetworkAndCidr).init(alloc);
    // Get the IPs in 32-bit unsigned integers (big-endian)
    var start_ipn = ipv4AsNumber(start_ip);
    const end_ipn = ipv4AsNumber(end_ip);
    const u32max: u32 = 0xFFFFFFFF;

    while (start_ipn <= end_ipn and start_ipn != u32max) {
        var n_trailing_zeros = @ctz(start_ipn);
        var current: u32 = 0;

        // Switch all those bits to 1
        // See if that takes us past the end IP address
        // Try one fewer in a loop until it doesn't pass the end
        while (true) {
            const i_to_nth = math.shl(u32, 1, n_trailing_zeros);
            current = start_ipn | (i_to_nth - 1);
            if (current > end_ipn) {
                n_trailing_zeros -= 1;
                continue;
            }
            break;
        }

        var host_bits: u8 = 0;

        // Loop until the masked `current` and `start_ipn` are equal
        while (true) {
            const pow_two = try std.math.powi(u32, 2, host_bits);
            const prefix_pow = @as(u32, pow_two);
            const current_masked = current & prefix_pow;
            const start_ipn_masked = start_ipn & prefix_pow;
            if (current_masked == start_ipn_masked) {
                break;
            }

            host_bits += 1;
        }

        // Adjust the prefix length to calculate the CIDR
        const prefix_len = 32 - host_bits;

        const o1: u8 = @intCast(@shrExact(start_ipn & 0xFF000000, 24));
        const o2: u8 = @intCast(@shrExact(start_ipn & 0x00FF0000, 16));
        const o3: u8 = @intCast(@shrExact(start_ipn & 0x0000FF00, 8));
        const o4: u8 = @intCast(@shrExact(start_ipn & 0x000000FF, 0));
        const bytes: [4]u8 = [_]u8{
            o1, o2, o3, o4,
        };
        // Create the network address from the bytes
        const ip_n = mem.readInt(u32, mem.asBytes(&bytes), .little);

        // Append the network and CIDR to the results array
        try results.append(.{
            .network = Ip4Address{
                .sa = .{
                    .port = 0,
                    .addr = ip_n,
                },
            },
            .cidr = prefix_len,
        });

        start_ipn = current + 1;
    }

    return results;
}

const testCase = struct {
    start: Ip4Address,
    end: Ip4Address,
    exp_net: []const u8,
    exp_cidr: u8,
};

const expectedResult = struct {
    network: []const u8,
    cidr: u8,
};

test "Single CIDR block IPv4 ranges" {
    const alloc = std.heap.page_allocator;
    const test_cases = [_]testCase{
        .{ .start = try ip4("10.10.10.0"), .end = try ip4("10.10.10.255"), .exp_net = "10.10.10.0", .exp_cidr = 24 },
        .{ .start = try ip4("10.10.10.128"), .end = try ip4("10.10.10.255"), .exp_net = "10.10.10.128", .exp_cidr = 25 },
        .{ .start = try ip4("50.7.0.0"), .end = try ip4("50.7.0.255"), .exp_net = "50.7.0.0", .exp_cidr = 24 },
        .{ .start = try ip4("50.7.0.0"), .end = try ip4("50.7.255.255"), .exp_net = "50.7.0.0", .exp_cidr = 16 },
        .{ .start = try ip4("50.2.0.0"), .end = try ip4("50.3.255.255"), .exp_net = "50.2.0.0", .exp_cidr = 15 },
        .{ .start = try ip4("50.16.0.0"), .end = try ip4("50.19.255.255"), .exp_net = "50.16.0.0", .exp_cidr = 14 },
        .{ .start = try ip4("50.21.176.0"), .end = try ip4("50.21.191.255"), .exp_net = "50.21.176.0", .exp_cidr = 20 },
        .{ .start = try ip4("50.22.0.0"), .end = try ip4("50.23.255.255"), .exp_net = "50.22.0.0", .exp_cidr = 15 },
        .{ .start = try ip4("50.28.0.0"), .end = try ip4("50.28.127.255"), .exp_net = "50.28.0.0", .exp_cidr = 17 },
        .{ .start = try ip4("50.31.0.0"), .end = try ip4("50.31.127.255"), .exp_net = "50.31.0.0", .exp_cidr = 17 },
        .{ .start = try ip4("50.31.128.0"), .end = try ip4("50.31.255.255"), .exp_net = "50.31.128.0", .exp_cidr = 17 },
        .{ .start = try ip4("50.56.0.0"), .end = try ip4("50.57.255.255"), .exp_net = "50.56.0.0", .exp_cidr = 15 },
        .{ .start = try ip4("50.58.197.0"), .end = try ip4("50.58.197.255"), .exp_net = "50.58.197.0", .exp_cidr = 24 },
        .{ .start = try ip4("50.60.0.0"), .end = try ip4("50.61.255.255"), .exp_net = "50.60.0.0", .exp_cidr = 15 },
        .{ .start = try ip4("50.62.0.0"), .end = try ip4("50.63.255.255"), .exp_net = "50.62.0.0", .exp_cidr = 15 },
        .{ .start = try ip4("50.85.0.0"), .end = try ip4("50.85.255.255"), .exp_net = "50.85.0.0", .exp_cidr = 16 },
        .{ .start = try ip4("50.87.0.0"), .end = try ip4("50.87.255.255"), .exp_net = "50.87.0.0", .exp_cidr = 16 },
        .{ .start = try ip4("50.97.0.0"), .end = try ip4("50.97.255.255"), .exp_net = "50.97.0.0", .exp_cidr = 16 },
        .{ .start = try ip4("50.112.0.0"), .end = try ip4("50.112.255.255"), .exp_net = "50.112.0.0", .exp_cidr = 16 },
        .{ .start = try ip4("50.115.0.0"), .end = try ip4("50.115.15.255"), .exp_net = "50.115.0.0", .exp_cidr = 20 },
        .{ .start = try ip4("50.115.32.0"), .end = try ip4("50.115.47.255"), .exp_net = "50.115.32.0", .exp_cidr = 20 },
        .{ .start = try ip4("50.115.112.0"), .end = try ip4("50.115.127.255"), .exp_net = "50.115.112.0", .exp_cidr = 20 },
        .{ .start = try ip4("50.115.128.0"), .end = try ip4("50.115.143.255"), .exp_net = "50.115.128.0", .exp_cidr = 20 },
        .{ .start = try ip4("50.115.160.0"), .end = try ip4("50.115.175.255"), .exp_net = "50.115.160.0", .exp_cidr = 20 },
        .{ .start = try ip4("50.115.224.0"), .end = try ip4("50.115.239.255"), .exp_net = "50.115.224.0", .exp_cidr = 20 },
        .{ .start = try ip4("50.116.0.0"), .end = try ip4("50.116.63.255"), .exp_net = "50.116.0.0", .exp_cidr = 18 },
        .{ .start = try ip4("50.116.64.0"), .end = try ip4("50.116.127.255"), .exp_net = "50.116.64.0", .exp_cidr = 18 },
        .{ .start = try ip4("50.117.0.0"), .end = try ip4("50.117.127.255"), .exp_net = "50.117.0.0", .exp_cidr = 17 },
        .{ .start = try ip4("50.118.128.0"), .end = try ip4("50.118.255.255"), .exp_net = "50.118.128.0", .exp_cidr = 17 },
        .{ .start = try ip4("51.4.0.0"), .end = try ip4("51.5.255.255"), .exp_net = "51.4.0.0", .exp_cidr = 15 },
    };

    for (test_cases) |case| {
        const result = try GetCIDRsInRange(alloc, case.start, case.end);
        defer result.deinit();

        const actualNet = try ip4str(alloc, result.items[0].network);
        defer alloc.free(actualNet);
        try expectEqual(1, result.items.len);
        try expectEqualStrings(case.exp_net, actualNet);
        try expectEqual(case.exp_cidr, result.items[0].cidr);
    }
}

test "Multiple CIDR block IPv4 ranges" {
    // Arrange
    const alloc = std.heap.page_allocator;
    const start = try ip4("51.10.0.0");
    const end = try ip4("51.24.255.255");
    const expected = [_]expectedResult{
        .{ .network = "51.10.0.0", .cidr = 15 },
        .{ .network = "51.12.0.0", .cidr = 14 },
        .{ .network = "51.16.0.0", .cidr = 13 },
        .{ .network = "51.24.0.0", .cidr = 16 },
    };

    //Act
    const result = try GetCIDRsInRange(alloc, start, end);
    defer result.deinit();
    // for (result.items) |item| {
    //     std.debug.print("Network: {}, CIDR: {}\n", .{ item.network, item.cidr });
    // }

    // Assert
    try expectEqual(4, result.items.len);

    for (expected, 0..) |value, i| {
        const actual = try ip4str(alloc, result.items[i].network);
        defer alloc.free(actual);
        try expectEqualStrings(value.network, actual);
        try expectEqual(value.cidr, result.items[i].cidr);
    }
}
