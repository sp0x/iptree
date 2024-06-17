const std = @import("std");
const inet = @cImport(@cInclude("arpa/inet.h"));
const expect = std.testing.expect;
const posix = std.posix;

pub const Prefix = struct {
    family: u8,
    bitlen: u32,
    address: std.net.Address,

    // Create a new prefix using an address, byte array for the IP address and a network mask
    pub fn fromFamily(family: u8, addr: []const u8, mask: u8) !Prefix {
        const maxMaskValue: u8 = if (family == posix.AF.INET) @as(u8, 32) else @as(u8, 128);
        var targetMaskValue = mask;
        if (mask > maxMaskValue) {
            targetMaskValue = maxMaskValue;
        }
        const ipAddress = try std.net.Address.parseIp(addr, 0);
        sanitizeMask(ipAddress, family, mask, maxMaskValue);

        return Prefix{ .family = family, .bitlen = targetMaskValue, .address = ipAddress };
    }

    pub fn asNumber(self: *const Prefix) u32 {
        const bytes = std.mem.asBytes(&self.address.in.sa.addr);
        return std.mem.readInt(u32, bytes, .big);
    }

    pub fn isSupersetOf(self: *const Prefix, other: *const Prefix) bool {
        if (other.family != self.family)
            return false;

        const mask = self.bitlen / 8;
        const maskBits = self.bitlen % 8;
        const otherBytes = std.mem.asBytes(if (self.family == posix.AF.INET) &other.address.in.sa.addr else &other.address.in6.sa.addr);
        const selfBytes = std.mem.asBytes(if (self.family == posix.AF.INET) &self.address.in.sa.addr else &self.address.in6.sa.addr);

        for (selfBytes, 0..) |_, i| {
            if (selfBytes[i] != otherBytes[i]) {
                return false;
            }
        }

        if (maskBits == 0) {
            return true;
        }

        const maskByte = ~0 << (8 - maskBits);
        return (selfBytes[mask] & maskByte) == (otherBytes[mask] & maskByte);
    }

    pub fn isSubsetOf(self: *const Prefix, other: *const Prefix) bool {
        if (self.family != other.family) {
            return false;
        }

        const mask = other.bitlen / 8;
        const maskBits = other.bitlen % 8;
        const otherBytes = std.mem.asBytes(if (self.family == posix.AF.INET) &other.address.in.sa.addr else &other.address.in6.sa.addr);
        const selfBytes = std.mem.asBytes(if (self.family == posix.AF.INET) &self.address.in.sa.addr else &self.address.in6.sa.addr);

        for (selfBytes, 0..) |_, i| {
            if (selfBytes[i] != otherBytes[i]) {
                return false;
            }
        }

        if (maskBits == 0) {
            return true;
        }

        const maskByte = ~0 << (8 - maskBits);
        return (selfBytes[mask] & maskByte) == (otherBytes[mask] & maskByte);
    }
};

fn sanitizeMask(addr: std.net.Address, family: u8, masklen: u8, maskbits: u8) void {
    const selfBytes = std.mem.asBytes(if (family == posix.AF.INET) &addr.in.sa.addr else &addr.in6.sa.addr);
    const i = masklen / 8;
    const j = masklen % 8;
    if (j != 0) {
        selfBytes[i] &= (~0) << (8 - j);
        i += 1;
    }

    while (i < maskbits / 8) {
        selfBytes[i] = 0;
    }
}

test "prefix" {
    const prefix = try Prefix.fromFamily(posix.AF.INET, "192.168.0.0", 24);
    try expect(prefix.family == posix.AF.INET);
    try expect(prefix.bitlen == 24);
    try expect(prefix.address.in.sa.addr == 43200);
}
