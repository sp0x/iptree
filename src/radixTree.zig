const std = @import("std");
const posix = std.posix;
const net = std.net;
const mem = std.mem;
const math = std.math;
const testing = std.testing;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const Prefix = @import("prefix.zig").Prefix;
const utils = @import("utils.zig");
const NodeMod = @import("node.zig");
const Node = NodeMod.Node;
const NodeData = NodeMod.NodeData;
const print = std.debug.print;
const builtin = @import("builtin");

// Currently only IPv4 is supported, later on this should be extended to IPv6
const maxBits: u8 = 32;

pub const SearchResult = struct { node: ?*const Node, data: ?NodeData };
const WalkOp = *const fn (node: *Node, state: *anyopaque) void;

pub const RadixTree = struct {
    allocator: mem.Allocator,
    head: ?*Node = null,
    numberOfNodes: u32 = 0,

    pub fn init(allocator: mem.Allocator) RadixTree {
        return .{ .allocator = allocator };
    }

    pub fn format(
        self: RadixTree,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        if (fmt.len != 0) std.fmt.invalidFmtError(fmt, self);
        _ = options;
        if (self.head == null) {
            try out_stream.print("RadixTree is empty", .{});
            return;
        }
        try out_stream.print("{any}", .{self.head});
    }

    fn initializeHead(self: *RadixTree, prefix: Prefix) !*Node {
        if (prefix.networkBits > 128) {
            return error.OutOfRange;
        }

        self.head = try self.allocator.create(Node);
        self.head.?.* = Node{
            .networkBits = prefix.networkBits,
            .prefix = prefix,
            .parent = null,
            .left = null,
            .right = null,
            .data = undefined,
        };
        self.numberOfNodes += 1;
        return self.head.?;
    }

    pub fn insertValue(self: *RadixTree, prefix: Prefix, data: NodeData) !void {
        const node = try self.insert(prefix);
        node.data = data;
    }

    pub fn insert(self: *RadixTree, prefix: Prefix) !*Node {
        if (self.head == null) {
            return self.initializeHead(prefix) catch |err| {
                std.debug.print("error during head initialization: {}\n", .{err});
                return error.OutOfMemory;
            };
        }

        const addressBytes = prefix.asBytes();
        const newPrefixNetworkBits = prefix.networkBits;
        var currentNode = self.head.?;
        // Find a place where to insert the new node, trying to find a wider CIDR to insert into.
        while (currentNode.networkBits < newPrefixNetworkBits or currentNode.prefix.isEmpty()) {
            const low_3_bits: u8 = currentNode.networkBits & 0x07;
            const node_fits = currentNode.networkBits < maxBits;
            const mask = math.shr(u8, 0x80, low_3_bits);
            // Shift by 3 to the right to divide by 8
            const bits_right = cmp_bits(addressBytes[currentNode.networkBits >> 3], mask);

            if (node_fits and bits_right) {
                if (currentNode.right == null) break;
                currentNode = currentNode.right.?;
            } else {
                if (currentNode.left == null) break;
                currentNode = currentNode.left.?;
            }
        }
        const testAddressBytes = currentNode.prefix.asBytes();
        const bitsToCheck = if (currentNode.networkBits < newPrefixNetworkBits)
            currentNode.networkBits
        else
            newPrefixNetworkBits;
        var differingBitIndex: u8 = 0;
        var i: u8 = 0;
        while (i * 8 < bitsToCheck) : (i += 1) {
            const r = addressBytes[i] ^ testAddressBytes[i];
            if (r == 0) {
                differingBitIndex = (i + 1) * 8;
                continue;
            }

            var j: u8 = 0;
            while (j < 8) : (j += 1) {
                const shiftedJ = math.shr(u8, 0x80, j);
                if (cmp_bits(r, shiftedJ)) break;
            }
            differingBitIndex = i * 8 + j;
            break;
        }
        if (differingBitIndex > bitsToCheck) differingBitIndex = bitsToCheck;

        var parent = currentNode.parent;
        while (parent != null and parent.?.networkBits >= differingBitIndex) {
            currentNode = parent.?;
            parent = currentNode.parent;
        }

        if (differingBitIndex == newPrefixNetworkBits and currentNode.networkBits == newPrefixNetworkBits) {
            if (currentNode.prefix.isEmpty()) {
                currentNode.prefix = prefix; // try prefix.clone();
            }
            return currentNode;
        }

        var resultingNode: *Node = undefined;
        var newNode = try self.allocator.create(Node);
        newNode.* = Node{
            .networkBits = prefix.networkBits,
            .prefix = prefix, // try prefix.clone(),
            .parent = null,
            .left = null,
            .right = null,
            .data = undefined,
        };
        self.numberOfNodes += 1;
        if (currentNode.networkBits == differingBitIndex) {
            newNode.parent = currentNode;
            const tmpMask: u8 = currentNode.networkBits & 0x07;
            if (currentNode.networkBits < maxBits and cmp_bits(addressBytes[currentNode.networkBits >> 3], math.shr(u8, 0x80, tmpMask))) {
                currentNode.right = newNode;
            } else {
                currentNode.left = newNode;
            }
            return newNode;
        }
        if (newPrefixNetworkBits == differingBitIndex) {
            const tmpMask: u8 = newPrefixNetworkBits & 0x07;
            print("New node: {d} {d}\n", .{ newPrefixNetworkBits, differingBitIndex });
            if (newPrefixNetworkBits < maxBits and cmp_bits(testAddressBytes[newPrefixNetworkBits >> 3], math.shr(u8, 0x80, tmpMask))) {
                newNode.right = currentNode;
            } else {
                newNode.left = currentNode;
            }
            newNode.parent = currentNode.parent;
            if (currentNode.parent == null) {
                self.head = newNode;
            } else if (currentNode.parent.?.right == currentNode) {
                currentNode.parent.?.right = newNode;
                return currentNode.parent.?.right.?;
            } else {
                currentNode.parent.?.left = newNode;
                return currentNode.parent.?.left.?;
            }
        } else {
            var glueNode = try self.allocator.create(Node);
            glueNode.* = Node{
                .networkBits = differingBitIndex,
                .prefix = Prefix.empty(),
                .parent = currentNode.parent,
                .data = undefined,
                .left = null,
                .right = null,
            };
            const currentParent = currentNode.parent orelse null;
            newNode.parent = glueNode;
            currentNode.parent = glueNode;
            self.numberOfNodes += 1;
            resultingNode = newNode;

            const tmpMask: u8 = differingBitIndex & 0x07;
            const shiftedMask = math.shr(u8, 0x80, tmpMask);
            // Figure out where to put the new node, left or right.
            if (differingBitIndex < maxBits and cmp_bits(addressBytes[differingBitIndex >> 3], shiftedMask)) {
                glueNode.right = newNode;
                glueNode.left = currentNode;
                // std.debug.print("Glueing {d}: {d} {d}(new)\n", .{ differingBitIndex, currentNode.networkBits, newNode.networkBits });
            } else {
                // std.debug.print("Glueing {d}: {d}(new) {d}\n", .{ differingBitIndex, newNode.networkBits, currentNode.networkBits });
                glueNode.right = currentNode;
                glueNode.left = newNode;
            }

            if (currentNode == self.head) {
                self.head = glueNode;
            } else if (currentParent.?.right == currentNode) {
                currentParent.?.right = glueNode;
            } else if (currentParent.?.left == currentNode) {
                currentParent.?.left = glueNode;
            }

            // Do assertions only in debug mode to avoid performance overhead in release builds.
            if (builtin.mode == .Debug) {
                try glueNode.assert_integrity();
            }
        }

        if (builtin.mode == .Debug) {
            try resultingNode.assert_integrity();
        }

        return resultingNode;
    }

    pub fn searchExact(self: *RadixTree, prefix: Prefix) ?*Node {
        var currentNode = self.head orelse return null;
        const addressBytes = prefix.asBytes();
        const bitLength = prefix.networkBits;

        while (currentNode.networkBits < bitLength) {
            const bitIndex = currentNode.networkBits >> 3;
            const bitMask = math.shr(u8, 0x80, currentNode.networkBits & 0x07);
            if (cmp_bits(addressBytes[bitIndex], bitMask)) {
                currentNode = currentNode.right orelse return null;
            } else {
                currentNode = currentNode.left orelse return null;
            }
        }

        if (currentNode.networkBits > bitLength || currentNode.prefix.isEmpty) {
            return null;
        }

        const currentPrefixBytes = currentNode.prefix.asBytes();
        if (compareAddressesWithMask(currentPrefixBytes, addressBytes, bitLength)) {
            return currentNode;
        }

        return null;
    }

    pub fn walk(self: *RadixTree, node: *Node, f: WalkOp, state: *anyopaque) void {
        if (node.left) |left| {
            self.walk(left, f, state);
        }
        if (node.right) |right| {
            self.walk(right, f, state);
        }
        f(node, state);
    }

    /// Search for the best match for a given IP/CIDR in the radix tree.
    pub fn SearchBest(self: *RadixTree, prefixToFind: Prefix) ?SearchResult {
        if (self.head == null) {
            return null;
        }

        var stack = std.ArrayList(*const Node).init(std.heap.page_allocator);
        defer stack.deinit();
        var nodeLp: ?*Node = self.head.?;

        const prefixToFindBytes = prefixToFind.asBytes();
        const needleCidr = prefixToFind.networkBits;
        // Starting from the head node, traverse the tree
        while (nodeLp.?.networkBits < needleCidr) {
            const crNode = nodeLp.?.*;
            if (!crNode.prefix.isEmpty()) {
                stack.append(nodeLp orelse unreachable) catch return null;
            }

            if (cmp_bits(prefixToFindBytes[crNode.networkBits >> 3], math.shr(u8, 0x80, crNode.networkBits & 0x07))) {
                // Possible issue here!
                nodeLp = crNode.right;
            } else {
                // Or here
                nodeLp = crNode.left;
            }

            if (nodeLp == null) break;
        }

        if (nodeLp != null and !nodeLp.?.prefix.isEmpty()) {
            stack.append(nodeLp.?) catch return null;
        }

        while (stack.items.len > 0) {
            const stackNode = stack.pop();
            if (stackNode == null) continue;
            const nodeAddrBytes = stackNode.?.prefix.asBytes();
            const stack_pfx = stackNode.?.prefix;

            const doPrefixesMatch = compareAddressesWithMask(prefixToFindBytes, nodeAddrBytes, stack_pfx.networkBits);

            if (doPrefixesMatch and stack_pfx.networkBits <= needleCidr) {
                const mergeResult = mergeParentStack(stackNode.?, &stack);

                return .{
                    .node = stackNode.?,
                    .data = mergeResult,
                };
            }
        }

        return null;
    }

    pub fn destroyNode(self: *RadixTree, node: *Node) void {
        if (node.left) |left| {
            self.destroyNode(left);
        }
        if (node.right) |right| {
            self.destroyNode(right);
        }
        self.allocator.destroy(node);
    }

    /// Free the entire radix tree, including all nodes.
    /// This will deallocate all memory used by the tree.
    /// If the tree is empty, it does nothing.
    pub fn free(self: *RadixTree) void {
        if (self.head == null) return;

        self.destroyNode(self.head.?);
        self.head = null;
        self.numberOfNodes = 0;
        _ = self.allocator; // Prevent unused variable warning
    }
};

fn mergeParentStack(seedNode: *const Node, stack: *std.ArrayList(*const Node)) ?NodeData {
    var mergeResult: ?NodeData = seedNode.data;

    while (stack.items.len > 0) {
        const parent = stack.pop();
        if (parent == null) {
            continue;
        }

        if (mergeResult == null or !mergeResult.?.isComplete()) {
            // We overwrite the data if the parent is a smaller subnet, not a bigger one
            mergeResult = mergeOrSwap(mergeResult, parent.?.data, false);
        } else {
            break;
        }
    }

    return mergeResult;
}

fn mergeOrSwap(dest: ?NodeData, src: ?NodeData, overwrite: bool) ?NodeData {
    if (src == null) {
        return dest;
    }

    if (dest == null) {
        return src;
    }

    var nonNullDestination = dest orelse return null;

    nonNullDestination.merge(&src.?, overwrite);
    return nonNullDestination;
}

/// Compares bits and checks if all masked bits are set.
fn cmp_bits(byte: u8, mask: u8) bool {
    return byte & mask == mask;
}

pub fn compareAddressesWithMask(address: []const u8, dest: []const u8, mask: u32) bool {
    const segmentLength = mask / 8;
    const addressSegment = address[0..segmentLength];
    const destSegment = dest[0..segmentLength];

    if (std.mem.eql(u8, addressSegment, destSegment)) {
        const n = segmentLength;
        const m = math.shl(u8, 255, (8 - (mask % 8))) & 0xFF;

        if (mask % 8 == 0 or ((address[n] & m) == (dest[n] & m))) {
            return true;
        }
    }

    return false;
}

comptime {
    @import("std").testing.refAllDecls(@This());
}

test "construction" {
    const allocator = std.testing.allocator;

    var tree = RadixTree.init(allocator);
    defer {
        tree.free();
    }
    const pfx = try Prefix.fromCidr("1.0.0.0/8");
    const n1 = try tree.insert(pfx);
    n1.data = .{ .asn = 5 };

    try expect(tree.head != null);
    try expect(tree.numberOfNodes == 1);
}

test "mergeParentStack" {
    const allocator = std.testing.allocator;
    const pfx = try Prefix.fromIpAndMask("1.0.0.0", 32);
    const node = NodeMod.New(.{
        .asn = null,
        .datacenter = null,
    }, pfx);
    var stack = std.ArrayList(*const Node).init(allocator);

    try stack.append(&NodeMod.New(.{
        .asn = 52,
        .datacenter = null,
    }, pfx));
    try stack.append(&NodeMod.New(.{
        .asn = null,
        .datacenter = true,
    }, pfx));
    defer stack.deinit();

    const mergedData = mergeParentStack(&node, &stack);

    try expect(mergedData != null);
    try expect(mergedData.?.datacenter == true);
    try expect(mergedData.?.asn == 52);
}

test "construction and adding multiple items" {
    const allocator = std.testing.allocator;
    var tree = RadixTree.init(allocator);
    defer tree.free();
    const pfx = try Prefix.fromCidr("1.0.0.0/8");
    const pfx2 = try Prefix.fromCidr("2.0.0.0/8");
    const n1 = try tree.insert(pfx);
    const n2 = try tree.insert(pfx2);
    n1.data = .{ .asn = 5 };
    n2.data = .{ .datacenter = true };

    try expect(tree.head != null);
    try expect(tree.numberOfNodes == 3);
}

test "adding many nodes" {
    const allocator = std.testing.allocator;
    var tree = RadixTree.init(allocator);
    defer tree.free();
    const pfx = try Prefix.fromCidr("1.0.20.0/24");
    const pfx2 = try Prefix.fromCidr("1.0.21.0/24");
    const pfx3 = try Prefix.fromCidr("1.0.0.0/24");
    const pfx4 = try Prefix.fromCidr("1.0.4.0/24");
    const pfx5 = try Prefix.fromCidr("1.0.5.0/24");
    const pfx6 = try Prefix.fromCidr("1.0.6.0/24");
    const n1 = try tree.insert(pfx);
    const n2 = try tree.insert(pfx2);
    _ = try tree.insert(pfx3);
    _ = try tree.insert(pfx4);
    _ = try tree.insert(pfx5);
    const n6 = try tree.insert(pfx6);

    n1.data = .{ .asn = 5 };
    n2.data = .{ .datacenter = true };
    n6.data = .{ .asn = 25, .datacenter = true };
    //    print("Tree: {any}\n", .{tree});
    n1.data = .{ .asn = 5 };
    n2.data = .{ .datacenter = true };

    try std.testing.expectEqual(11, tree.numberOfNodes);
}

test "building a tree with a thousand nodes" {
    const allocator = std.testing.allocator;
    var tree = RadixTree.init(allocator);
    defer tree.free();
    var ip_n: u32 = 0;
    for (0..1000) |i| {
        ip_n += 256;
        const address: net.Address = .{
            .in = .{
                .sa = .{
                    .addr = @as(u32, ip_n),
                    .port = 0,
                },
            },
        };
        var ip_buff = std.ArrayList(u8).init(allocator);
        defer ip_buff.deinit();
        try utils.ip_fmt(address, &ip_buff.writer());
        try ip_buff.appendSlice("/24");

        const pfx = try Prefix.fromCidr(ip_buff.items);
        const node = try tree.insert(pfx);
        if (i % 2 == 0) {
            node.data = .{ .asn = @intCast(i) };
        } else {
            node.data = .{ .datacenter = true };
        }
    }
    // We should have more than 1000 nodes, because of the way the tree works.
    // Some nodes will be merged, some will be added as children.
    // The exact number of nodes will depend on the distribution of the IPs.
    try expectEqual(1999, tree.numberOfNodes);
    try expect(tree.head != null);
    var state = walk_state{
        .found_asns = 0,
        .found_datacenters = 0,
    };
    tree.walk(tree.head.?, struct {
        pub fn call(node: *Node, st: *anyopaque) void {
            // This is just a placeholder to ensure the walk works.
            // In a real test, you might want to check the node's data or properties.
            node.assert_integrity() catch |err| {
                std.debug.print("Node integrity check failed: {}\n", .{err});
            };
            if (node.data == null) {
                return;
            }
            // Increment the counters based on the node's data.
            var lp_st: *walk_state = @ptrCast(@alignCast(st));
            if (node.data.?.asn) |_| {
                lp_st.found_asns += 1;
            }
            if (node.data.?.datacenter) |_| {
                lp_st.found_datacenters += 1;
            }
        }
    }.call, &state);

    try expectEqual(state.found_asns, 500);
    try expectEqual(state.found_datacenters, 500);
}

const walk_state = struct {
    found_asns: u16,
    found_datacenters: u16,
};

test "addition or update when adding" {
    const allocator = std.testing.allocator;
    var tree = RadixTree.init(allocator);
    defer tree.free();
    const pfx = try Prefix.fromCidr("1.0.0.0/8");
    const pfx2 = try Prefix.fromCidr("2.0.0.0/8");

    _ = try tree.insert(pfx);
    _ = try tree.insert(pfx2);
}

test "should be searchable" {
    const allocator = std.testing.allocator;
    var tree = RadixTree.init(allocator);
    defer tree.free();
    const parent = try Prefix.fromCidr("1.0.0.0/8");
    const ip_seg_2 = try Prefix.fromCidr("2.0.0.0/8");
    const node = try tree.insert(parent);
    node.data = .{ .asn = 5 };
    _ = try tree.insert(ip_seg_2);

    const pfx = try Prefix.fromCidr("1.1.1.0/32");
    const result = tree.SearchBest(pfx);
    try expect(result != null);
    try expect(result.?.node != null);
    const data = result.?.data.?;
    try expect(data.asn == 5);
    try expect(data.datacenter == null);
}

test "when parent has more data then data should be merged in" {
    const allocator = std.testing.allocator;
    var tree = RadixTree.init(allocator);
    defer tree.free();
    const parent = try Prefix.fromCidr("1.0.0.0/8");
    const child = try Prefix.fromCidr("1.1.0.0/16");
    try tree.insertValue(parent, .{ .asn = 5 });
    try tree.insertValue(child, .{ .datacenter = true });

    const pfx = try Prefix.fromCidr("1.1.1.0/32");

    const result = tree.SearchBest(pfx);

    try expect(result != null);
    try expect(result.?.node != null);
    const data = result.?.data.?;
    try testing.expectEqual(5, data.asn);
    try expect(data.datacenter.?);
}
