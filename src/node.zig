const Prefix = @import("prefix.zig").Prefix;
const utils = @import("utils.zig");
const assert = utils.assert;
const std = @import("std");
const testing = std.testing;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const print = std.debug.print;

pub const NodeData = struct {
    asn: ?u32 = null,
    datacenter: ?bool = null,
    name: ?[]const u8 = null,

    pub fn isComplete(self: *const NodeData) bool {
        return self.asn != null and self.datacenter != null;
    }

    pub fn merge(self: *NodeData, other: *const NodeData, overwrite: bool) void {
        var asnVal = self.asn orelse other.asn;
        var datacenterVal = self.datacenter orelse other.datacenter;
        var nameVal = self.name orelse other.name;
        if (overwrite and other.name != null) {
            nameVal = other.name;
        }
        if (overwrite and other.asn != null) {
            asnVal = other.asn;
        }
        if (overwrite and other.datacenter != null) {
            datacenterVal = other.datacenter;
        }

        self.asn = asnVal;
        self.datacenter = datacenterVal;
        self.name = nameVal;
    }

    pub fn format(
        self: NodeData,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        if (fmt.len != 0) std.fmt.invalidFmtError(fmt, self);
        _ = options;
        if (self.name != null) {
            try out_stream.print("name: {s} ", .{self.name.?});
        }
        try out_stream.print("asn: {?}, datacenter: {?}", .{ self.asn, self.datacenter });
    }

    pub fn free(self: *NodeData, allocator: std.mem.Allocator) void {
        if (self.name != null) {
            allocator.free(self.name.?);
            self.name = null;
        }
    }
};

// A string formatting method for NodeData

pub const Node = struct {
    prefix: Prefix,
    parent: ?*Node = null,
    left: ?*Node = null,
    right: ?*Node = null,
    data: ?NodeData = null,
    networkBits: u8 = 0,

    pub fn format(
        self: Node,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        if (fmt.len != 0) std.fmt.invalidFmtError(fmt, self);
        _ = options;
        try self.printNode(out_stream, "", "");
    }

    /// Injects an overwrite instead of the current node. After this you may want to assign the current node to the left or the right side of the overwrite.
    /// Note: this detaches the current node **fully**, meaning all parent, left and right sides are removed.
    pub fn swap(self: *Node, overwrite: *Node) void {
        overwrite.parent = self.parent;

        if (self.parent) |p| {
            if (p.left == self) {
                p.left = overwrite;
            } else if (p.right == self) {
                p.right = overwrite;
            } else {
                unreachable("Parent not linked to child");
            }
        }

        // Set the overwrite's children ?
        overwrite.left = self.left;
        overwrite.right = self.right;
        //

        if (self.left) |l| l.parent = overwrite;
        if (self.right) |r| r.parent = overwrite;

        self.detach();
    }
    /// Sets the *self* node as a child of the 'super' node, managing the current parent assignment.
    /// The left and right side of *self* are not modified.
    pub fn set_super(self: *Node, super: *Node) void {
        super.parent = self.parent;

        if (self.parent) |p| {
            if (p.left == self) {
                p.left = super;
            } else if (p.right == self) {
                p.right = super;
            } else {
                unreachable("Parent not linked to child");
            }
        }

        // Make the super node our parent.
        self.parent = super;
    }

    pub fn detach(self: *Node) void {
        self.parent = null;
        self.left = null;
        self.right = null;
    }

    pub fn set_left(self: *Node, left: *Node) void {
        self.left = left;
        left.parent = self;
    }

    pub fn set_right(self: *Node, right: *Node) void {
        self.right = right;
        right.parent = self;
    }

    fn printNode(self: *const Node, out_stream: anytype, indent: []const u8, pfx: []const u8) !void {
        try out_stream.print("{s}{s}{any}[{any}]\n", .{ indent, pfx, self.prefix, self.data });
        const has_children = self.left != null or self.right != null;
        if (!has_children) return;

        var buffer = [_]u8{undefined} ** 100;
        const indentation = try std.fmt.bufPrint(&buffer, "{s}  ", .{indent});

        if (self.left) |left| {
            try left.printNode(out_stream, indentation, "├── ");
        }
        if (self.right) |right| {
            try right.printNode(out_stream, indentation, "└── ");
        }
    }

    /// Free the node's data if it exists. To free the node's children, call free on them directly or use a radix tree's free method instead.
    pub fn free(self: *Node, allocator: std.mem.Allocator) void {
        if (self.data != null) {
            self.data.?.free(allocator);
        }
    }

    pub fn assert_integrity(self: *const Node) !void {
        // Assert that:
        // Child nodes have this node as a parent.
        // This node's parent has this node as a child.
        // The prefix is valid

        assert(self.prefix.is_valid(), "Invalid prefix found: {any}", .{self.prefix});

        if (self.left != null) {
            // std.debug.print("Comparing left parent with self: {*} == {*}\n", .{ self.left.?.*.parent, self });
            assert(self.left.?.*.parent == self, "Left child does not have node as parent.", .{});
        }
        if (self.right != null) {
            // std.debug.print("Comparing right parent with self: {*} == {*}\n", .{ self.right.?.*.parent, self });
            assert(self.right.?.*.parent == self, "Right child does not have node as parent.", .{});
        }

        if (self.parent != null) {
            assert(self.parent.?.*.left == self or self.parent.?.*.right == self, "Current node's parent doesn't have the node as a child, even though node's parent is set.", .{});
        }
        // assert we dont have recursive parent
        var current = self.parent;
        while (current) |node| {
            assert(node != self, "Node is its own ancestor", .{});
            current = node.parent;
        }
    }
};

pub fn New(data: NodeData, prefix: Prefix) Node {
    return Node{
        .prefix = prefix,
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

test "swapping simple" {
    const allocator = std.testing.allocator;
    const pfx = try Prefix.fromIpAndMask("1.1.1.1", 32);
    const pfx2 = try Prefix.fromIpAndMask("1.1.1.2", 32);
    var n1: Node = Node{ .prefix = pfx };
    var n2: Node = Node{ .prefix = pfx2 };
    defer n1.free(allocator);
    defer n2.free(allocator);
    n1.swap(&n2);

    assert(&n1 != n2.parent, "N2 should remain without a parent", .{});
    assert(n2.parent == null, "Swap shouldn't set parent in target node", .{});
}

test "swapping advanced" {
    // Arrange
    const allocator = std.testing.allocator;
    const pfx = try Prefix.fromIpAndMask("1.1.1.1", 32);
    const pfx2 = try Prefix.fromIpAndMask("1.1.1.2", 32);
    const pfx3 = try Prefix.fromIpAndMask("1.1.1.3", 32);
    const pfx4 = try Prefix.fromIpAndMask("1.1.1.4", 32);
    const pfx5 = try Prefix.fromIpAndMask("1.1.1.5", 32);
    const pfxswap = try Prefix.fromIpAndMask("1.1.1.9", 32);
    var n1: Node = .{ .prefix = pfx };
    var n2: Node = .{ .prefix = pfx2 };
    var n3: Node = .{ .prefix = pfx3 };
    var n4: Node = .{ .prefix = pfx4 };
    var n5: Node = .{ .prefix = pfx5 };
    var nswap: Node = .{ .prefix = pfxswap };
    defer n1.free(allocator);
    defer n2.free(allocator);
    defer n3.free(allocator);
    defer n4.free(allocator);

    n1.set_left(&n2);
    n1.set_right(&n3);
    n3.set_left(&n4);
    n3.set_right(&n5);
    //   n1
    // n2   n3 <-- We swap here, changing n3 with nswap
    //    n4    n5
    // Act
    n3.swap(&nswap);
    // Assert
    assert(n1.right == &nswap, "Swapping should change parent, child CORRECT side", .{});
    assert(n1.left == &n2, "No other changes on parent", .{});
    assert(n4.parent == &nswap, "Child's parent should change after swapping the parent", .{});
    assert(n5.parent == &nswap, "Child's parent should change after swapping the parent", .{});
    assert(n3.parent == null, "Swapping detaches the target node.", .{});
    assert(n3.left == null, "Swapping detaches the target node.", .{});
    assert(n3.right == null, "Swapping detaches the target node.", .{});
    try n1.assert_integrity();
}

test "swapping root" {
    // Arrange
    const allocator = std.testing.allocator;
    const pfx = try Prefix.fromIpAndMask("1.1.1.1", 32);
    const pfx2 = try Prefix.fromIpAndMask("1.1.1.2", 32);
    const pfx3 = try Prefix.fromIpAndMask("1.1.1.3", 32);
    const pfx4 = try Prefix.fromIpAndMask("1.1.1.4", 32);
    const pfx5 = try Prefix.fromIpAndMask("1.1.1.5", 32);
    const pfxswap = try Prefix.fromIpAndMask("1.1.1.9", 32);
    var n1: Node = .{ .prefix = pfx };
    var n2: Node = .{ .prefix = pfx2 };
    var n3: Node = .{ .prefix = pfx3 };
    var n4: Node = .{ .prefix = pfx4 };
    var n5: Node = .{ .prefix = pfx5 };
    var nswap: Node = .{ .prefix = pfxswap };
    defer n1.free(allocator);
    defer n2.free(allocator);
    defer n3.free(allocator);
    defer n4.free(allocator);

    n1.set_left(&n2);
    n1.set_right(&n3);
    n3.set_left(&n4);
    n3.set_right(&n5);
    //   n1 <-- We swap here, at the root
    // n2   n3
    //    n4    n5
    // Act
    n1.swap(&nswap);
    // Assert
    assert(nswap.right == &n3, "Swapping should change parent, child CORRECT side", .{});
    assert(nswap.left == &n2, "No other changes on parent", .{});
    assert(n4.parent == &n3, "Child's parent should change after swapping the parent", .{});
    assert(n5.parent == &n3, "Child's parent should change after swapping the parent", .{});
    assert(n1.parent == null, "Swapping detaches the target node.", .{});
    assert(n1.left == null, "Swapping detaches the target node.", .{});
    assert(n1.right == null, "Swapping detaches the target node.", .{});
    try nswap.assert_integrity();
    try n1.assert_integrity();
}

test "super" {
    const allocator = std.testing.allocator;
    const pfx = try Prefix.fromIpAndMask("1.1.1.1", 32);
    const pfx2 = try Prefix.fromIpAndMask("1.1.1.2", 32);
    const pfx3 = try Prefix.fromIpAndMask("1.1.1.3", 32);
    const pfx4 = try Prefix.fromIpAndMask("1.1.1.4", 32);
    const pfx5 = try Prefix.fromIpAndMask("1.1.1.5", 32);
    const pfxsuper = try Prefix.fromIpAndMask("1.1.1.9", 32);
    var n1: Node = .{ .prefix = pfx };
    var n2: Node = .{ .prefix = pfx2 };
    var n3: Node = .{ .prefix = pfx3 };
    var n4: Node = .{ .prefix = pfx4 };
    var n5: Node = .{ .prefix = pfx5 };
    var nsuper: Node = .{ .prefix = pfxsuper };
    defer n1.free(allocator);
    defer n2.free(allocator);
    defer n3.free(allocator);
    defer n4.free(allocator);

    n1.set_left(&n2);
    n1.set_right(&n3);
    n3.set_left(&n4);
    n3.set_right(&n5);
    //   n1
    // n2   n3 <-- we set the super here
    //    n4    n5
    // Act
    n3.set_super(&nsuper);

    assert(n3.parent == &nsuper, "Setting the super node should reassign parent-child nodes", .{});
    assert(n1.right == &nsuper, "set_super should assign the node on the correct side.", .{});
    assert(n3.left == &n4, "Left side should not change after set_super", .{});
    assert(n3.right == &n5, "Right side should not change after set_super", .{});
}

test "Integrity check" {
    // Arrange
    const pfx = try Prefix.fromIpAndMask("1.1.1.1", 0);
    var root_node = Node{
        .prefix = pfx,
        .parent = null,
        .left = null,
        .right = null,
        .data = .{
            .asn = 0,
            .datacenter = true,
        },
    };
    var left_node = Node{
        .prefix = pfx,
        .parent = &root_node,
        .left = null,
        .right = null,
        .data = .{
            .asn = 1,
            .datacenter = false,
        },
    };
    var right_node = Node{
        .prefix = pfx,
        .parent = &root_node,
        .left = null,
        .right = null,
        .data = .{
            .asn = 2,
            .datacenter = true,
        },
    };
    root_node.left = &left_node;
    root_node.right = &right_node;

    // Act & assert
    try root_node.assert_integrity();
    try left_node.assert_integrity();
    try right_node.assert_integrity();
}

test "Allocation safety" {
    const allocator = std.testing.allocator;
    const pfx = try Prefix.fromIpAndMask("1.1.1.1", 0);
    var root_node = Node{
        .prefix = pfx,
        .parent = null,
        .left = null,
        .right = null,
        .data = .{
            .asn = 0,
            .datacenter = true,
            .name = try allocator.dupe(u8, "root"),
        },
    };
    var left_node = Node{
        .prefix = pfx,
        .parent = &root_node,
        .left = null,
        .right = null,
        .data = .{
            .asn = 1,
            .datacenter = false,
            .name = try allocator.dupe(u8, "left"),
        },
    };
    var right_node = Node{
        .prefix = pfx,
        .parent = &root_node,
        .left = null,
        .right = null,
        .data = .{
            .asn = 2,
            .datacenter = true,
            .name = try allocator.dupe(u8, "right"),
        },
    };
    root_node.left = &left_node;
    root_node.right = &right_node;
    // Act & assert
    try root_node.assert_integrity();
    try left_node.assert_integrity();
    try right_node.assert_integrity();
    defer root_node.free(allocator);
    defer left_node.free(allocator);
    defer right_node.free(allocator);
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

    try expectEqual(55, nodeData1.asn);
    try expectEqual(true, nodeData1.datacenter);
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

    try expectEqual(56, nodeData1.asn);
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

    try expectEqual(55, nodeData1.asn);
    try expectEqual(true, nodeData1.datacenter);
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

    try expectEqual(55, nodeData1.asn);
    try expect(nodeData1.datacenter.?);
}
