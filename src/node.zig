const Prefix = @import("prefix.zig").Prefix;
const std = @import("std");
const expect = std.testing.expect;

pub const NodeData = struct {
    asn: u32,
};

const Node = struct {
    prefix: Prefix,
    parent: ?*Node,
    left: ?*Node,
    right: ?*Node,
    data: ?NodeData,
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
        },
    };
    try expect(node.data.asn == 0);
}
