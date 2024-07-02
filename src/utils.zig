const std = @import("std");
const mem = std.mem;
const posix = std.posix;

pub fn resolveFamily(ipAddress: []const u8) u8 {
    if (mem.containsAtLeast(u8, ipAddress, 1, ":")) {
        return posix.AF.INET6;
    } else {
        return posix.AF.INET;
    }
}
