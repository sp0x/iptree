const Prefix = @import("prefix.zig").Prefix;
const std = @import("std");
const testing = std.testing;
const expect = std.testing.expect;

pub const NodeData = struct {
    asn: ?u32 = null,
    datacenter: ?bool = null,

    pub fn isComplete(self: *const NodeData) bool {
        return self.asn != null and self.datacenter != null;
    }

    pub fn merge(self: *NodeData, other: *const NodeData, overwrite: bool) void {
        var asnVal = self.asn orelse other.asn;
        var datacenterVal = self.datacenter orelse other.datacenter;
        if (overwrite and other.asn != null) {
            asnVal = other.asn;
        }
        if (overwrite and other.datacenter != null) {
            datacenterVal = other.datacenter;
        }

        self.asn = asnVal;
        self.datacenter = datacenterVal;
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

pub fn New(data: NodeData, prefix: Prefix) Node {
    return Node{
        .prefix = prefix,
        .parent = null,
        .left = null,
        .right = null,
        .data = data,
    };
}

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
        .asn = 55,
        .datacenter = null,
    };
    const nodeData2: NodeData = .{
        .asn = null,
        .datacenter = true,
    };

    nodeData1.merge(&nodeData2, true);

    try expect(nodeData1.asn == 55);
    try expect(nodeData1.datacenter == true);
}

test "Node merge overwrite" {
    var nodeData1: NodeData = .{
        .asn = 55,
        .datacenter = null,
    };
    const nodeData2: NodeData = .{
        .asn = 56,
        .datacenter = true,
    };

    nodeData1.merge(&nodeData2, true);

    try testing.expectEqual(56, nodeData1.asn);
    try expect(nodeData1.datacenter.?);
}

test "Node merge without overwrite" {
    var nodeData1: NodeData = .{
        .asn = 55,
        .datacenter = null,
    };
    const nodeData2: NodeData = .{
        .asn = null,
        .datacenter = true,
    };

    nodeData1.merge(&nodeData2, false);

    try expect(nodeData1.asn == 55);
    try expect(nodeData1.datacenter == true);
}

test "Node merge without overwrite and value change" {
    var nodeData1: NodeData = .{
        .asn = 55,
        .datacenter = null,
    };
    const nodeData2: NodeData = .{
        .asn = 56,
        .datacenter = true,
    };

    nodeData1.merge(&nodeData2, false);

    try testing.expectEqual(55, nodeData1.asn);
    try expect(nodeData1.datacenter.?);
}
