const std = @import("std");
const Prefix = @import("prefix.zig").Prefix;
const newPrefix = @import("prefix.zig").newPrefix;



pub const RadixTree = struct {
    head: Node,
    // fn insert(self: *RadixTree, prefix: Prefix) *Node {}
};

comptime {
    @import("std").testing.refAllDecls(@This());
}
