const std = @import("std");
const Prefix = @import("prefix.zig").Prefix;
const newPrefix = @import("prefix.zig").newPrefix;

const NodeData = struct {
    asn: u32,
};

const Node = struct {
    prefix: Prefix,
    parent: *Node,
    left: *Node,
    right: *Node,
    data: *NodeData,
};

pub const RadixTree = struct {
    head: Node,
    // fn insert(self: *RadixTree, prefix: Prefix) *Node {}
};

comptime {
    @import("std").testing.refAllDecls(@This());
}
