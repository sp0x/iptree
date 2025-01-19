const std = @import("std");
const mem = std.mem;
const math = std.math;
const bufprint = std.fmt.bufPrint;
const posix = std.posix;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqual = std.testing.expectEqual;
const Address = std.net.Address;
const Managed = math.big.int.Managed;
const net = std.net;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub fn resolveFamily(ipAddress: []const u8) u8 {
    if (mem.containsAtLeast(u8, ipAddress, 1, ":")) {
        return posix.AF.INET6;
    } else {
        return posix.AF.INET;
    }
}

// A combination of a network address and a CIDR mask
pub const NetworkAndCidr = struct {
    network: Address,
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

fn getMostSignificantBit(value: u64) u8 {
    var bit: u8 = 0;
    var currentValue = value;
    while (currentValue != 0) {
        bit += 1;
        currentValue >>= 1;
    }
    return bit;
}

pub fn asNumber(address: Address) u32 {
    return switch (address.any.family) {
        posix.AF.INET6 => address.in6.sa.addr,
        posix.AF.INET => mem.readInt(u32, mem.asBytes(address.in.sa.addr), .big),
        else => unreachable,
    };
}

/// Goes from the least significant bit to the most significant bit and compares them if they are the same.
fn compare_bits(byte1: u8, byte2: u8, index: anytype) bool {
    const bit1 = math.shr(u8, byte1, index) & 1;
    const bit2 = math.shr(u8, byte2, index) & 1;
    return bit1 == bit2;
}

/// Go byte by byte untill a diff is found, then get the trailing 0s for hosts
pub fn get_min_network_bits(start_ip: []const u8, end_ip: []const u8) u8 {
    // Cases:
    // 1:
    // 00110011.00000100.00000000.00000000
    // 00110011.00000101.11111111.11111111 -
    // --------------^ bytes are same up untill here and the start has no bits to the right, so we can use a single range
    // 2:
    // 00110011.00001010.00000000.00000000
    // 00110011.00001101.11111111.11111111
    // -------------^ bytes are same up untill here, but the start IP has a bit to the right, so we must break it up in smaller ranges

    var common_bits: u8 = 0;
    for (0..4) |i| {
        const xor = start_ip[i] ^ end_ip[i];
        if (xor == 0) {
            common_bits += 8;
            continue;
        }

        const start = start_ip[i];
        const end = end_ip[i];

        // Go bit by bit to find the first diff
        var current_segment_common_bits: u8 = 0;
        var j: u8 = 7;
        while (j >= 0) {
            if (!compare_bits(start, end, j)) {
                current_segment_common_bits = 8 - (@as(u8, j) + 1); // because j is 0 indexed(0-7)
                break;
            }
            j -= 1;
        }

        std.debug.print("current_segment_common_bits between {d} and {d} = {d}\n", .{ start, end, current_segment_common_bits });

        const start_ctz = @ctz(start);
        std.debug.print("start ctz: {d}\n", .{start_ctz});
        // If the treailing zeros + the common bits are 8, then we can use a single range
        if (start_ctz + current_segment_common_bits >= 8) {
            common_bits += current_segment_common_bits;
            break;
        }

        // Else the start IP has bit(s) to the right, so we must break it up in smaller ranges
        common_bits += 8 - @ctz(start_ip[i]);
        break;
    }
    return common_bits;
}

fn getNetworkAndCidrFromIpv4(allocator: Allocator, start_ip: net.Ip4Address, end_ip: net.Ip4Address) !std.ArrayList(NetworkAndCidr) {
    var results = std.ArrayList(NetworkAndCidr).init(allocator);
    const start_ip_bytes = mem.asBytes(&start_ip.sa.addr);
    const end_ip_bytes = mem.asBytes(&end_ip.sa.addr);

    const min_network_bits = get_min_network_bits(start_ip_bytes, end_ip_bytes);
    const host_bits: u8 = 32 - min_network_bits;
    const hosts_mask = math.shl(u32, 1, host_bits) - 1;
    var temp_ip = net.Ip4Address{
        .sa = .{
            .port = 0,
            .addr = start_ip.sa.addr,
        },
    };
    var temp_ip_bytes = mem.asBytes(&temp_ip.sa.addr);
    while (true) {
        var cr_ip = net.Ip4Address{ // Maybe use Address.initIp4
            .sa = .{
                .port = 0,
                .addr = undefined,
            },
        };
        var cr_bytes = mem.asBytes(&cr_ip.sa.addr);
        @memcpy(cr_bytes, temp_ip_bytes);
        try results.append(.{
            .network = Address{ .in = cr_ip },
            .cidr = min_network_bits,
        });

        const cr_num: u32 = mem.readInt(u32, cr_bytes, .big);
        const range_end: u32 = cr_num | hosts_mask;
        const range_end_be = @byteSwap(range_end);
        const range_end_bytes = mem.asBytes(&range_end_be);
        const next_range_start: u32 = @byteSwap(range_end + 1);
        const next_range_start_bytes = mem.asBytes(&next_range_start);
        @memcpy(temp_ip_bytes, next_range_start_bytes);
        if (mem.eql(u8, range_end_bytes, end_ip_bytes)) { // TODO: use rage end instead of next_range_start.
            break;
        }
        _ = &cr_bytes;
    }

    _ = &temp_ip_bytes;

    return results;
}

// fn getNetworkAndCidrFromIpv6(startIp: Address, endIp: Address) !NetworkAndCidr {
//     var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
//     defer std.debug.assert(general_purpose_allocator.deinit() == .ok);
//     const gpa = general_purpose_allocator.allocator();

//     const start_ip_slice = startIp.in6.sa.addr[0..];
//     const end_ip_slice = endIp.in6.sa.addr[0..];

//     var startIpNum: Managed = try Managed.initSet(gpa, startIp.in6.sa.addr);
//     defer startIpNum.deinit();
//     var endIpNum: Managed = try Managed.initSet(gpa, endIp.in6.sa.addr);
//     defer endIpNum.deinit();
//     var ipDiff: Managed = try Managed.init(gpa);
//     try ipDiff.sub(@constCast(&endIpNum), @constCast(&startIpNum));
//     try ipDiff.addScalar(&ipDiff, 1);
//     //TODO: figure out a way to convert a [16]u8 to a big int
//     const hostCount = try ipDiff.to(u64);
//     const hostBitsReserved = getMostSignificantBit(hostCount) - 1;

//     const mask = 128 - hostBitsReserved;
//     var network_ip = net.Ip6Address{
//         .sa = posix.sockaddr.in6{
//             .scope_id = 0,
//             .port = mem.nativeToBig(u16, 0),
//             .flowinfo = 0,
//             .addr = undefined,
//         },
//     };
//     var network_slice: *[16]u8 = network_ip.sa.addr[0..];
//     for (0..16) |i| {
//         network_slice[i] = start_ip_slice[i] & end_ip_slice[i];
//     }
//     var result_addr = Address{ .in6 = network_ip };
//     result_addr.any.family = posix.AF.INET6;

//     return .{
//         .network = result_addr,
//         .cidr = mask,
//     };
// }

pub fn GetNetworkAndCidrFromIps(allocator: Allocator, start_ip: Address, end_ip: Address) !std.ArrayList(NetworkAndCidr) {
    return switch (start_ip.any.family) {
        // posix.AF.INET6 => try getNetworkAndCidrFromIpv6(startIp, endIp),
        posix.AF.INET => getNetworkAndCidrFromIpv4(allocator, start_ip.in, end_ip.in),
        else => unreachable,
    };
}

fn ip(s: []const u8) Address {
    return Address.parseIp(s, 0) catch unreachable;
}

test "get_min_network_bits" {
    fn print_ip(ip: []const u8) void {
        std.debug.print("{d}.{d}.{d}.{d}", .{ ip[0], ip[1], ip[2], ip[3] });
    }

    // Arrange
    const test_buffer = [_]u8{
        @as(u8, 51), 0x4, 0x0,  0x0,
        @as(u8, 51), 0x5, 0xff, 0xff,
        @as(u8, 15),
    };

    // Act
    var i: usize = 0;
    while (true) {
        const start_ip = test_buffer[i .. i + 4];
        const end_ip = test_buffer[(i + 1) * 4 .. (i + 1) * 4 + 4];
        const expected = test_buffer[(i + 1) * 4 + 1 .. (i + 1) * 4 + 1 + 1][0];
        std.debug.print("start_ip: ");        print_ip(start_ip);
        std.debug.print(" end_ip: ");        print_ip(end_ip);
        std.debug.print
        std.debug.print("start_ip: {d}.{d}.{d}.{d}\n", .{ start_ip[0], start_ip[1], start_ip[2], start_ip[3] });    
        std.debug.print("\n");

        std.fmt.format("{s}", .{std.fmt.fmtSliceHexLower(&[_]u8{ 1, 2, 3, 15, 13, 12 })});
        std.debug.print("start_ip: {d}.{d}.{d}.{d}\n", .{ start_ip[0], start_ip[1], start_ip[2], start_ip[3] });
        // Act
        const result = get_min_network_bits(start_ip, end_ip);
        // Assert
        try expectEqual(expected, result);
        i += 1;
    }
}

test "getNetworkAndCidrFromIps" {
    // Arrange
    const ranges = [_][2][]const u8{
        // [_][]const u8{ "50.7.0.0-50.7.0.255", "50.7.0.0:0/24" },
        // [_][]const u8{ "50.7.0.0-50.7.255.255", "50.7.0.0:0/16" },
        // [_][]const u8{ "50.2.0.0-50.3.255.255", "50.2.0.0:0/15" },
        // [_][]const u8{ "50.16.0.0-50.19.255.255", "50.16.0.0:0/14" },
        // [_][]const u8{ "50.21.176.0-50.21.191.255", "50.21.176.0:0/20" },
        // [_][]const u8{ "50.22.0.0-50.23.255.255", "50.22.0.0:0/15" },
        // [_][]const u8{ "50.28.0.0-50.28.127.255", "50.28.0.0:0/17" },
        // [_][]const u8{ "50.31.0.0-50.31.127.255", "50.31.0.0:0/17" },
        // [_][]const u8{ "50.31.128.0-50.31.255.255", "50.31.128.0:0/17" },
        // [_][]const u8{ "50.56.0.0-50.57.255.255", "50.56.0.0:0/15" },
        // [_][]const u8{ "50.58.197.0-50.58.197.255", "50.58.197.0:0/24" },
        // [_][]const u8{ "50.60.0.0-50.61.255.255", "50.60.0.0:0/15" },
        // [_][]const u8{ "50.62.0.0-50.63.255.255", "50.62.0.0:0/15" },
        // [_][]const u8{ "50.85.0.0-50.85.255.255", "50.85.0.0:0/16" },
        // [_][]const u8{ "50.87.0.0-50.87.255.255", "50.87.0.0:0/16" },
        // [_][]const u8{ "50.97.0.0-50.97.255.255", "50.97.0.0:0/16" },
        // [_][]const u8{ "50.112.0.0-50.112.255.255", "50.112.0.0:0/16" },
        // [_][]const u8{ "50.115.0.0-50.115.15.255", "50.115.0.0:0/20" },
        // [_][]const u8{ "50.115.32.0-50.115.47.255", "50.115.32.0:0/20" },
        // [_][]const u8{ "50.115.112.0-50.115.127.255", "50.115.112.0:0/20" },
        // [_][]const u8{ "50.115.128.0-50.115.143.255", "50.115.128.0:0/20" },
        // [_][]const u8{ "50.115.160.0-50.115.175.255", "50.115.160.0:0/20" },
        // [_][]const u8{ "50.115.224.0-50.115.239.255", "50.115.224.0:0/20" },
        // [_][]const u8{ "50.116.0.0-50.116.63.255", "50.116.0.0:0/18" },
        // [_][]const u8{ "50.116.64.0-50.116.127.255", "50.116.64.0:0/18" },
        // [_][]const u8{ "50.117.0.0-50.117.127.255", "50.117.0.0:0/17" },
        // [_][]const u8{ "50.118.128.0-50.118.255.255", "50.118.128.0:0/17" },
        //[_][]const u8{ "51.4.0.0-51.5.255.255", "51.4.0.0:0/15" },
        // 00110011.00000100.00000000.00000000
        // 00110011.00000101.11111111.11111111
        // ---------------^ bytes are same up untill here and the start has no bits to the right, so we can use a single range

        [_][]const u8{ "51.10.0.0-51.13.255.255", "51.10.0.0:0/15,51.12.0.0:0/15" },
        // 00110011.00001010.00000000.00000000
        // 00110011.00001101.11111111.11111111
        // -------------^ bytes are same up untill here, but the start IP has a bit to the right, so we must break it up in smaller ranges

        // TODO: find a way to differentiate the two cases
    };

    var string_builder = std.ArrayList(u8).init(std.testing.allocator);
    defer string_builder.deinit();

    for (ranges) |range| {
        var split = std.mem.split(u8, range[0], "-");
        const start_ip_str = split.next() orelse unreachable;
        const end_ip_str = split.next() orelse unreachable;
        const start_ip = ip(start_ip_str);
        const end_ip = ip(end_ip_str);

        // Act
        const results = try GetNetworkAndCidrFromIps(std.testing.allocator, start_ip, end_ip);
        defer results.deinit();

        // Assert
        for (0.., results.items) |i, result| {
            try string_builder.writer().print("{}", .{result});
            if (i < results.items.len - 1) {
                try string_builder.writer().print(",", .{});
            }
        }

        const final_str = string_builder.items;
        expectEqualStrings(range[1], final_str) catch {
            std.debug.print("While processing: {s} - {s}\n", .{ start_ip_str, end_ip_str });
        };
        string_builder.clearAndFree();
    }
}
