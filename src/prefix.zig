const std = @import("std");
const expect = std.testing.expect;
const Address = std.net.Address;
const posix = std.posix;
const math = std.math;
const ranges = @import("ranges.zig");
const utils = @import("utils.zig");

/// Represents a network address with it's CIDR mask
pub const Prefix = struct {
    networkBits: u8 = 0,
    address: Address,

    pub fn is_empty(self: *const Prefix) bool {
        return self.address.in.sa.addr == 0;
    }

    pub fn is_valid(self: *const Prefix) bool {
        return switch (self.address.any.family) {
            posix.AF.INET => self.networkBits <= 32,
            posix.AF.INET6 => self.networkBits <= 128,
            else => {
                std.debug.panic("Only IPv4 and IPv6 prefixes are supported. Found prefix: {any} family {d}", .{ self, self.address.any.family });
            },
        };
    }

    pub fn empty() Prefix {
        return Prefix{ .address = Address{ .in = .{ .sa = .{ .addr = 0, .port = 0 } } } };
    }

    pub fn fromCidr(cidr: []const u8) !Prefix {
        var addr: []const u8 = undefined;
        var mask: u8 = 0;
        const slashPosition = std.mem.indexOf(u8, cidr, "/");
        if (slashPosition == null) {
            addr = cidr;
            mask = 0;
        } else {
            addr = cidr[0..slashPosition.?];
            mask = try std.fmt.parseInt(u8, cidr[slashPosition.? + 1 ..], 10);
        }

        return try Prefix.fromIpAndMask(addr, mask);
    }

    pub fn from_ipv4(addr: std.net.Address, mask: u8) Prefix {
        var maxMaskValue: u8 = 32;
        if (addr.any.family == posix.AF.INET6) {
            maxMaskValue = 128;
        }
        var targetMaskValue = mask;
        if (mask > maxMaskValue) {
            targetMaskValue = maxMaskValue;
        }
        const ipx = sanitizeMask(addr, mask, maxMaskValue);

        return Prefix{ .networkBits = targetMaskValue, .address = ipx };
    }

    // Create a new prefix using an address, byte array for the IP address and a network mask
    pub fn fromIpAndMask(addr: []const u8, mask: u8) !Prefix {
        const family = ranges.GetFamily(addr);
        const maxMaskValue: u8 = if (family == posix.AF.INET) @as(u8, 32) else @as(u8, 128);
        var targetMaskValue = mask;
        if (mask > maxMaskValue) {
            targetMaskValue = maxMaskValue;
        }
        var ipAddress = try Address.parseIp(addr, 0);
        ipAddress = sanitizeMask(ipAddress, mask, maxMaskValue);

        if (targetMaskValue > 128) {
            return error.OutOfBands;
        }

        return Prefix{ .networkBits = targetMaskValue, .address = ipAddress };
    }

    pub fn asBytes(self: *const Prefix) []const u8 {
        return std.mem.asBytes(&self.address.in.sa.addr);
    }

    pub fn format(
        self: *const Prefix,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        if (fmt.len != 0) std.fmt.invalidFmtError(fmt, self);
        _ = options;

        try out_stream.print("{}/{d}", .{ self.address, self.networkBits });
    }

    pub fn isSupersetOf(self: *const Prefix, other: Prefix) bool {
        if (other.address.any.family != self.address.any.family)
            return false;

        const mask = self.networkBits / 8;
        const maskBits = self.networkBits % 8;
        const isv4 = self.address.any.family == posix.AF.INET;
        const otherBytes = if (isv4) std.mem.asBytes(&other.address.in.sa.addr) else std.mem.asBytes(&other.address.in6.sa.addr);
        const selfBytes = if (isv4) std.mem.asBytes(&self.address.in.sa.addr) else std.mem.asBytes(&self.address.in6.sa.addr);

        for (0..mask) |i| {
            if (selfBytes[i] != otherBytes[i]) {
                return false;
            }
        }

        if (maskBits == 0) {
            return true;
        }

        const maskByte = math.shl(u8, 255, 8 - maskBits);
        return (selfBytes[mask] & maskByte) == (otherBytes[mask] & maskByte);
    }

    pub fn isSubsetOf(self: *const Prefix, other: Prefix) bool {
        if (self.address.any.family != other.address.any.family) {
            return false;
        }

        const mask = other.networkBits / 8;
        const maskBits = other.networkBits % 8;
        const isv4 = self.address.any.family == posix.AF.INET;
        const otherBytes = if (isv4) std.mem.asBytes(&other.address.in.sa.addr) else std.mem.asBytes(&other.address.in6.sa.addr);
        const selfBytes = if (isv4) std.mem.asBytes(&self.address.in.sa.addr) else std.mem.asBytes(&self.address.in6.sa.addr);

        for (0..mask) |i| {
            if (selfBytes[i] != otherBytes[i]) {
                return false;
            }
        }

        if (maskBits == 0) {
            return true;
        }

        const maskByte = math.shl(u8, 255, 8 - maskBits);
        return (selfBytes[mask] & maskByte) == (otherBytes[mask] & maskByte);
    }
};

fn sanitizeMask(addr: Address, masklen: u8, maskbits: u8) Address {
    var i = @as(u8, masklen / 8);
    const j = @as(u8, masklen % 8);
    var addressNumber: u32 = addr.in.sa.addr;
    var bytes = std.mem.asBytes(&addressNumber);
    if (j != 0) {
        const amp = @as(u8, 8) - j;
        bytes[i] &= math.shl(u8, 255, amp);
        i += 1;
    }
    while (i < maskbits / 8) {
        bytes[i] = 0;
        i += 1;
    }

    return Address{ .in = .{
        .sa = .{
            .port = addr.getPort(),
            .addr = addressNumber,
        },
    } };
}

test "prefix from IP and mask" {
    const prefix = try Prefix.fromIpAndMask("192.168.0.0", 24);
    try expect(prefix.address.any.family == posix.AF.INET);
    try expect(prefix.networkBits == 24);
    try expect(prefix.address.in.sa.addr == 43200);
}

test "empty prefix construction" {
    const pfx: Prefix = Prefix{ .networkBits = 0, .address = Address{ .in = .{ .sa = .{ .addr = 0, .port = 0 } } } };
    try expect(pfx.is_empty());
}

test "prefixes should be sanitized correctly" {
    const prefix = try Prefix.fromIpAndMask("192.168.0.0", 24);
    const prefix2 = try Prefix.fromIpAndMask("192.168.0.1", 24);
    try expect(utils.ipv4_to_u32(prefix.address) == utils.ipv4_to_u32(prefix2.address));
}

test "prefixes should be able to be subsets" {
    const widerPrefix = try Prefix.fromIpAndMask("1.0.0.0", 8);
    const narrowerPrefix = try Prefix.fromIpAndMask("1.1.0.0", 16);

    try expect(narrowerPrefix.isSubsetOf(widerPrefix));
    try expect(!widerPrefix.isSubsetOf(narrowerPrefix));
}

test "prefixes should be able to be supersets" {
    const widerPrefix = try Prefix.fromIpAndMask("1.0.0.0", 8);
    const narrowerPrefix = try Prefix.fromIpAndMask("1.1.0.0", 16);

    try expect(widerPrefix.isSupersetOf(narrowerPrefix));
    try expect(!narrowerPrefix.isSupersetOf(widerPrefix));
}
