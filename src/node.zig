const Prefix = @import("prefix.zig").Prefix;
const std = @import("std");
const expect = std.testing.expect;

pub const NodeData = struct {
    asn: ?u32 = null,
    datacenter: ?bool = null,

    inline fn mergeValues(comptime T: type, self_value: ?T, other_value: ?T, overwrite: bool) ?T {
        return if (other_value) |value|
            (if (self_value == null or overwrite) value else self_value)
        else
            self_value;
    }

    pub fn isComplete(self: *const NodeData) bool {
        return self.asn != null and self.datacenter != null;
    }

    pub fn merge(self: *const NodeData, other: NodeData, overwrite: bool) NodeData {
        return NodeData{
            .asn = mergeValues(u32, self.asn, other.asn, overwrite),
            .datacenter = mergeValues(bool, self.datacenter, other.datacenter, overwrite),
        };
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
    const pfx = try Prefix.fromFamily(std.posix.AF.INET, "1.1.1.1", 0);
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
    const nodeData1: NodeData = .{
        .asn = 0,
        .datacenter = null,
    };
    const nodeData2: NodeData = .{
        .asn = null,
        .datacenter = true,
    };

    const mergeResult = nodeData1.merge(nodeData2, true);
    try expect(mergeResult.asn == 0);
    try expect(mergeResult.datacenter == true);
}
