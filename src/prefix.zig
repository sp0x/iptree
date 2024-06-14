const std = @import("std");

const PrefixAddress = union {
    sin: std.net.Address.IPv4,
    sin6: std.net.Address.IPv6,
};

pub const Prefix = struct {
    family: u32,
    bitlen: u32,
    addr: PrefixAddress,
};

// Create a new prefix using an address, byte array for the IP address and a network mask
pub fn fromFamily(family: u32, addr: []u8, mask: i8) Prefix {
    const maxMaskValue: u8 = if (family == std.net.Address.Family.IPv4) 32 else 128;
    if (mask < 0) {
        mask = maxMaskValue;
    }

    return Prefix{ .family = family, .bitlen = mask, .add = addr };
}

test "prefix" {
    const prefix = fromFamily(std.net.Address.Family.IPv4, &.{ 192, 168, 1, 1 }, 24);
    std.testing.expect(prefix.family == std.net.Address.Family.IPv4);
    std.testing.expect(prefix.bitlen == 24);
    std.testing.expect(prefix.addr.sin.addr[0] == 1);
}
