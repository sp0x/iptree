const Prefix = @import("prefix.zig").Prefix;
const std = @import("std");
const expect = std.testing.expect;

inline fn mergeValues(comptime T: type, dest_value: ?T, source_value: ?T, overwrite: bool) ?T {
    return if (source_value) |value|
        (if (dest_value == null or overwrite) value else dest_value)
    else
        dest_value;
}

pub const NodeData = struct {
    asn: ?u32 = null,
    datacenter: ?bool = null,

    pub fn isComplete(self: *const NodeData) bool {
        return self.asn != null and self.datacenter != null;
    }

    pub fn merge(self: *NodeData, other: *const NodeData, overwrite: bool) void {
        self.asn = mergeValues(u32, self.asn, other.asn, overwrite);
        self.datacenter = mergeValues(bool, self.datacenter, other.datacenter, overwrite);
    }
};

pub const Node = struct {
    prefix: Prefix,
    parent: ?*Node,
    left: ?*Node,
    right: ?*Node,
    data: ?NodeData,
    networkBits: u8 = 0,
};

test "Node" {
    const pfx = try Prefix.fromIpAndMask("1.1.1.1", 0);
    const node = Node{
        .prefix = pfx,
        .parent = null,
        .left = null,
        .right = null,
        .data = .{
            .asn = 0,
            .datacenter = true,
        },
    };
    try expect(node.data != null);
}

test "Node merge" {
    var nodeData1: NodeData = .{
        .asn = 0,
        .datacenter = null,
    };
    const nodeData2: NodeData = .{
        .asn = null,
        .datacenter = true,
    };

    nodeData1.merge(&nodeData2, true);

    try expect(nodeData1.asn == 0);
    try expect(nodeData1.datacenter == true);
}
