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
    parent: ?*Node,
    left: ?*Node,
    right: ?*Node,
    data: ?NodeData,
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

    pub fn free(self: *Node, allocator: std.mem.Allocator) void {
        print("Freeing node {any}: {any}\n", .{self.prefix, self.data});
        if (self.left) |left| {
            left.free(allocator);
        }
        if (self.right) |right| {
            right.free(allocator);
        }
        if (self.data) |_| {
            self.data.?.free(allocator);
        }
    }

    pub fn assert_integrity(self: *const Node) !void {
        // Assert that:
        // Child nodes have this node as a parent.
        // This node's parent has this node as a child.
        if (self.left != null) {
            // std.debug.print("Comparing left parent with self: {*} == {*}\n", .{ self.left.?.*.parent, self });
            assert(self.left.?.*.parent == self, "Left child parent mismatch", .{});
        }
        if (self.right != null) {
            // std.debug.print("Comparing right parent with self: {*} == {*}\n", .{ self.right.?.*.parent, self });
            assert(self.right.?.*.parent == self, "Right child parent mismatch", .{});
        }

        if (self.parent != null) {
            assert(self.parent.?.*.left == self or self.parent.?.*.right == self, "Parent child mismatch", .{});
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
