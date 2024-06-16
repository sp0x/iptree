const std = @import("std");
const math = std.math;
const posix = std.posix;

pub const Prefix = struct {
    family: u32,
    bitlen: u32,
    addr: std.net.Address,

    // Create a new prefix using an address, byte array for the IP address and a network mask
    pub fn fromFamily(family: u32, addr: []const u8, mask: u8) Prefix {
        const maxMaskValue: u8 = if (family == posix.AF.INET) @as(u8, 32) else @as(u8, 128);
        const targetMaskValue = std.math.min(mask, maxMaskValue);

        const addressByteCount = if (family == posix.AF.INET) 4 else 16;
        const buffer: [addressByteCount]u8 = undefined;

        std.posix.net.inet_pton(family, addr, buffer);

        return Prefix{ .family = family, .bitlen = targetMaskValue, .add = buffer };
    }
};

test "prefix" {
    const prefix = Prefix.fromFamily(posix.AF.INET, "192.168.0.0", 24);
    std.testing.expect(prefix.family == posix.AF.INET);
    std.testing.expect(prefix.bitlen == 24);
    std.testing.expect(prefix.addr.sin.addr[0] == 1);
}
