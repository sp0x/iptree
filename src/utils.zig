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
    var outcomes: [256][]const u8 = undefined;
    outcomes[0] = "1.1.1.0:0/32";
    outcomes[1] = "1.1.1.0:0/31";
    outcomes[2] = "1.1.1.0:0/31";
    outcomes[3] = "1.1.1.0:0/30";
    outcomes[4] = "1.1.1.0:0/30";

    for (0..5) |i| {
        const s = try bufprint(&buffer, "1.1.1.{d}", .{i});
        var copy_of_s = try std.testing.allocator.alloc(u8, s.len);
        @memcpy(copy_of_s[0..s.len], s);
        const result = try getNetworkAndCidrFromIps(ip("1.1.1.0"), ip(s));

        const actualResult = try bufprint(&buffer, "{}/{d}", .{ result.network, result.cidr });
        // TODO: implement expected outcomes..
        expectEqualStrings(outcomes[i], actualResult) catch {
            std.debug.print("While processing: {s} - {s}\n", .{ "1.1.1.0", copy_of_s });
        };

        std.testing.allocator.free(copy_of_s);
    }
}
