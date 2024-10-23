const std = @import("std");
const bufprint = std.fmt.bufPrint;
const mem = std.mem;
const posix = std.posix;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const Address = std.net.Address;
const Managed = std.math.big.int.Managed;
const net = std.net;
const ArrayList = std.ArrayList;

pub fn resolveFamily(ipAddress: []const u8) u8 {
    if (mem.containsAtLeast(u8, ipAddress, 1, ":")) {
        return posix.AF.INET6;
    } else {
        return posix.AF.INET;
    }
}

pub const NetworkAndCidr = struct {
    network: Address,
    cidr: u8,
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

fn getNetworkAndCidrFromIpv4(startIp: Address, endIp: Address) NetworkAndCidr {
    const start_ip_bytes = mem.asBytes(&startIp.in.sa.addr);
    const end_ip_bytes = mem.asBytes(&endIp.in.sa.addr);
    const startIpNum: u32 = mem.readInt(u32, start_ip_bytes, .big);
    const endIpNum: u32 = mem.readInt(u32, end_ip_bytes, .big);
    const hostCount: u64 = endIpNum - startIpNum + 1;
    const hostBitsReserved = getMostSignificantBit(hostCount) - 1;
    var network_ip = net.Ip4Address{
        .sa = posix.sockaddr.in{
            .port = 0,
            .addr = undefined,
        },
    };
    var network_slice = mem.asBytes(&network_ip.sa.addr);
    for (0..4) |i| {
        network_slice[i] = start_ip_bytes[i] & end_ip_bytes[i];
    }
    var result_addr = Address{ .in = network_ip };
    result_addr.any.family = posix.AF.INET;

    const mask = 32 - hostBitsReserved;
    return .{
        .network = result_addr,
        .cidr = mask,
    };
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

pub fn getNetworkAndCidrFromIps(startIp: Address, endIp: Address) !NetworkAndCidr {
    return switch (startIp.any.family) {
        // posix.AF.INET6 => try getNetworkAndCidrFromIpv6(startIp, endIp),
        posix.AF.INET => getNetworkAndCidrFromIpv4(startIp, endIp),
        else => unreachable,
    };
}

fn ip(s: []const u8) Address {
    return Address.parseIp(s, 0) catch unreachable;
}

test {
    var buffer: [32]u8 = undefined;
    const ranges: [27][2][]const u8 = [_][2][]const u8{
        [_][]const u8{ "50.7.0.0-50.7.0.255", "50.7.0.0:0/24" },
        [_][]const u8{ "50.7.0.0-50.7.255.255", "50.7.0.0:0/16" },
        [_][]const u8{ "50.2.0.0-50.3.255.255", "50.2.0.0:0/15" },
        [_][]const u8{ "50.16.0.0-50.19.255.255", "50.16.0.0:0/14" },
        [_][]const u8{ "50.21.176.0-50.21.191.255", "50.21.176.0:0/20" },
        [_][]const u8{ "50.22.0.0-50.23.255.255", "50.22.0.0:0/15" },
        [_][]const u8{ "50.28.0.0-50.28.127.255", "50.28.0.0:0/17" },
        [_][]const u8{ "50.31.0.0-50.31.127.255", "50.31.0.0:0/17" },
        [_][]const u8{ "50.31.128.0-50.31.255.255", "50.31.128.0:0/17" },
        [_][]const u8{ "50.56.0.0-50.57.255.255", "50.56.0.0:0/15" },
        [_][]const u8{ "50.58.197.0-50.58.197.255", "50.58.197.0:0/24" },
        [_][]const u8{ "50.60.0.0-50.61.255.255", "50.60.0.0:0/15" },
        [_][]const u8{ "50.62.0.0-50.63.255.255", "50.62.0.0:0/15" },
        [_][]const u8{ "50.85.0.0-50.85.255.255", "50.85.0.0:0/16" },
        [_][]const u8{ "50.87.0.0-50.87.255.255", "50.87.0.0:0/16" },
        [_][]const u8{ "50.97.0.0-50.97.255.255", "50.97.0.0:0/16" },
        [_][]const u8{ "50.112.0.0-50.112.255.255", "50.112.0.0:0/16" },
        [_][]const u8{ "50.115.0.0-50.115.15.255", "50.115.0.0:0/20" },
        [_][]const u8{ "50.115.32.0-50.115.47.255", "50.115.32.0:0/20" },
        [_][]const u8{ "50.115.112.0-50.115.127.255", "50.115.112.0:0/20" },
        [_][]const u8{ "50.115.128.0-50.115.143.255", "50.115.128.0:0/20" },
        [_][]const u8{ "50.115.160.0-50.115.175.255", "50.115.160.0:0/20" },
        [_][]const u8{ "50.115.224.0-50.115.239.255", "50.115.224.0:0/20" },
        [_][]const u8{ "50.116.0.0-50.116.63.255", "50.116.0.0:0/18" },
        [_][]const u8{ "50.116.64.0-50.116.127.255", "50.116.64.0:0/18" },
        [_][]const u8{ "50.117.0.0-50.117.127.255", "50.117.0.0:0/17" },
        [_][]const u8{ "50.118.128.0-50.118.255.255", "50.118.128.0:0/17" },
    };

    for (ranges) |range| {
        var split = std.mem.split(u8, range[0], "-");
        const start_ip_str = split.next() orelse unreachable;
        const end_ip_str = split.next() orelse unreachable;

        const startIp = ip(start_ip_str);
        const endIp = ip(end_ip_str);
        const result = try getNetworkAndCidrFromIps(startIp, endIp);
        const actualResult = try bufprint(&buffer, "{}/{d}", .{ result.network, result.cidr });

        expectEqualStrings(range[1], actualResult) catch {
            std.debug.print("While processing: {s} - {s}\n", .{ start_ip_str, end_ip_str });
        };
    }
}
