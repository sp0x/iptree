const std = @import("std");
const testing = std.testing;
pub const Prefix = @import("prefix.zig").Prefix;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    @import("std").testing.refAllDecls(@This());
    try testing.expect(add(3, 7) == 10);
}
