const std = @import("std");
const expect = std.testing.expect;
const Address = std.net.Address;
const posix = std.posix;
const math = std.math;

pub const Prefix = struct {
    family: u8,
    bitlen: u32,
    address: Address,

    pub fn isEmpty(self: *const Prefix) bool {
        return self.address.in.sa.addr == 0;
    }

    // Create a new prefix using an address, byte array for the IP address and a network mask
    pub fn fromFamily(family: u8, addr: []const u8, mask: u8) !Prefix {
        const maxMaskValue: u8 = if (family == posix.AF.INET) @as(u8, 32) else @as(u8, 128);
        var targetMaskValue = mask;
        if (mask > maxMaskValue) {
            targetMaskValue = maxMaskValue;
        }
        var ipAddress = try Address.parseIp(addr, 0);
        ipAddress = sanitizeMask(ipAddress, mask, maxMaskValue);

        return Prefix{ .family = family, .bitlen = targetMaskValue, .address = ipAddress };
    }

    pub fn asNumber(self: *const Prefix) u32 {
        const bytes = std.mem.asBytes(&self.address.in.sa.addr);
        return std.mem.readInt(u32, bytes, .big);
    }

    pub fn isSupersetOf(self: *const Prefix, other: Prefix) bool {
        if (other.family != self.family)
            return false;

        const mask = self.bitlen / 8;
        const maskBits = self.bitlen % 8;
        const isv4 = self.family == posix.AF.INET;
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
        if (self.family != other.family) {
            return false;
        }

        const mask = other.bitlen / 8;
        const maskBits = other.bitlen % 8;
        const isv4 = self.family == posix.AF.INET;
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

test "prefix" {
    const prefix = try Prefix.fromFamily(posix.AF.INET, "192.168.0.0", 24);
    try expect(prefix.family == posix.AF.INET);
    try expect(prefix.bitlen == 24);
    try expect(prefix.address.in.sa.addr == 43200);
}

test "empty prefix construction" {
    const pfx: Prefix = Prefix{ .family = posix.AF.INET, .bitlen = 0, .address = Address{ .in = .{ .sa = .{ .addr = 0, .port = 0 } } } };
    try expect(pfx.isEmpty());
}

test "prefixes should be sanitized correctly" {
    const prefix = try Prefix.fromFamily(posix.AF.INET, "192.168.0.0", 24);
    const prefix2 = try Prefix.fromFamily(posix.AF.INET, "192.168.0.1", 24);
    try expect(prefix.asNumber() == prefix2.asNumber());
}

test "prefixes should be able to be subsets" {
    const widerPrefix = try Prefix.fromFamily(posix.AF.INET, "1.0.0.0", 8);
    const narrowerPrefix = try Prefix.fromFamily(posix.AF.INET, "1.1.0.0", 16);

    try expect(narrowerPrefix.isSubsetOf(widerPrefix));
    try expect(!widerPrefix.isSubsetOf(narrowerPrefix));
}

test "prefixes should be able to be supersets" {
    const widerPrefix = try Prefix.fromFamily(posix.AF.INET, "1.0.0.0", 8);
    const narrowerPrefix = try Prefix.fromFamily(posix.AF.INET, "1.1.0.0", 16);

    try expect(widerPrefix.isSupersetOf(narrowerPrefix));
    try expect(!narrowerPrefix.isSupersetOf(widerPrefix));
}
