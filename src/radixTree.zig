const std = @import("std");
const mem = std.mem;
const math = std.math;
const testing = std.testing;
const expect = std.testing.expect;
const Prefix = @import("prefix.zig").Prefix;
const NodeMod = @import("node.zig");
const Node = NodeMod.Node;
const NodeData = NodeMod.NodeData;

// Currently only IPv4 is supported, later on this should be extended to IPv6
const maxBits: u8 = 32;

pub const SearchResult = struct { node: ?*const Node, data: ?NodeData };
const WalkOp = *const fn (node: *Node) void;

pub const RadixTree = struct {
    allocator: *const mem.Allocator = &std.heap.page_allocator,
    head: ?*Node = null,
    numberOfNodes: u32 = 0,

    pub fn init(allocator: *const mem.Allocator) RadixTree {
        return .{ .allocator = allocator };
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
        const node = try self.insertPrefix(prefix);
        node.data = data;
    }

    pub fn insertPrefix(self: *RadixTree, prefix: Prefix) !*Node {
        if (self.head == null) {
            return self.initializeHead(prefix) catch |err| {
                std.debug.print("error during head initialization: {}\n", .{err});
                return error.OutOfMemory;
            };
        }

        const addressBytes = prefix.asBytes();
        const newPrefixNetworkBits = prefix.networkBits;
        var currentNode = self.head.?;
        while (currentNode.networkBits < newPrefixNetworkBits or currentNode.prefix.isEmpty()) {
            const testShiftAmount: u8 = currentNode.networkBits & 0x07;
            if (currentNode.networkBits < maxBits and testBits(addressBytes[currentNode.networkBits >> 3], math.shr(u8, 0x80, testShiftAmount))) {
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
        var differBit: u8 = 0;
        var i: u8 = 0;
        while (i * 8 < bitsToCheck) : (i += 1) {
            const r = addressBytes[i] ^ testAddressBytes[i];
            if (r == 0) {
                differBit = (i + 1) * 8;
                continue;
            }

            var j: u8 = 0;
            while (j < 8) : (j += 1) {
                const shiftedJ = math.shr(u8, 0x80, j);
                if (testBits(r, shiftedJ)) break;
            }
            differBit = i * 8 + j;
            break;
        }
        if (differBit > bitsToCheck) differBit = bitsToCheck;

        var parent = currentNode.parent;
        while (parent != null and parent.?.networkBits >= differBit) {
            currentNode = parent.?;
            parent = currentNode.parent;
        }

        if (differBit == newPrefixNetworkBits and currentNode.networkBits == newPrefixNetworkBits) {
            if (currentNode.prefix.isEmpty()) {
                currentNode.prefix = prefix; // try prefix.clone();
            }
            return currentNode;
        }

        var resultingNode: *Node = undefined;
        var newNode = Node{
            .networkBits = prefix.networkBits,
            .prefix = prefix, // try prefix.clone(),
            .parent = null,
            .left = null,
            .right = null,
            .data = undefined,
        };
        self.numberOfNodes += 1;

        if (currentNode.networkBits == differBit) {
            newNode.parent = currentNode;
            const tmpMask: u8 = currentNode.networkBits & 0x07;
            if (currentNode.networkBits < maxBits and testBits(addressBytes[currentNode.networkBits >> 3], math.shr(u8, 0x80, tmpMask))) {
                currentNode.right = try self.allocator.create(Node);
                currentNode.right.?.* = newNode;
            } else {
                currentNode.left = try self.allocator.create(Node);
                currentNode.left.?.* = newNode;
            }
            return currentNode.left.?;
        }

        if (newPrefixNetworkBits == differBit) {
            const tmpMask: u8 = newPrefixNetworkBits & 0x07;
            if (newPrefixNetworkBits < maxBits and testBits(testAddressBytes[newPrefixNetworkBits >> 3], math.shr(u8, 0x80, tmpMask))) {
                newNode.right = currentNode;
            } else {
                newNode.left = currentNode;
            }

            newNode.parent = currentNode.parent;
            if (currentNode.parent == null) {
                self.head.?.* = newNode;
            } else if (currentNode.parent.?.right == currentNode) {
                currentNode.parent.?.right = try self.allocator.create(Node);
                currentNode.parent.?.right.?.* = newNode;
                return currentNode.parent.?.right.?;
            } else {
                currentNode.parent.?.left = try self.allocator.create(Node);
                currentNode.parent.?.left.?.* = newNode;
                return currentNode.parent.?.left.?;
            }
        } else {
            var glueNode = Node{
                .networkBits = differBit,
                .prefix = Prefix.empty(),
                .parent = currentNode.parent,
                .data = undefined,
                .left = null,
                .right = null,
            };
            self.numberOfNodes += 1;

            const tmpMask: u8 = differBit & 0x07;
            if (differBit < maxBits and testBits(addressBytes[differBit >> 3], math.shr(u8, 0x80, tmpMask))) {
                glueNode.right = try self.allocator.create(Node);
                glueNode.right.?.* = newNode;
                glueNode.left = currentNode;
                resultingNode = glueNode.right.?;
            } else {
                glueNode.left = try self.allocator.create(Node);
                glueNode.right = currentNode;
                glueNode.left.?.* = newNode;
                resultingNode = glueNode.left.?;
            }

            newNode.parent = &glueNode;
            if (currentNode.parent == null) {
                self.head.?.* = glueNode;
            } else if (currentNode.parent.?.right == currentNode) {
                currentNode.parent.?.right.?.* = glueNode;
            } else {
                currentNode.parent.?.left.?.* = glueNode;
            }

            if (currentNode.parent == null) {
                currentNode.parent = try self.allocator.create(Node);
            }
            currentNode.parent.?.* = glueNode;
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
            if (testBits(addressBytes[bitIndex], bitMask)) {
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

    pub fn walk(self: *RadixTree, node: *Node, f: WalkOp) void {
        if (node.left) |left| {
            self.walk(left, f);
        }
        if (node.right) |right| {
            self.walk(right, f);
        }
        f(node);
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

            if (testBits(prefixToFindBytes[crNode.networkBits >> 3], math.shr(u8, 0x80, crNode.networkBits & 0x07))) {
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
            const nodeAddrBytes = stackNode.prefix.asBytes();

            const doPrefixesMatch = compareAddressesWithMask(prefixToFindBytes, nodeAddrBytes, stackNode.prefix.networkBits);

            if (doPrefixesMatch and stackNode.prefix.networkBits <= needleCidr) {
                const mergeResult = mergeParentStack(stackNode, &stack);

                return .{
                    .node = stackNode,
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
};

fn mergeParentStack(seedNode: *const Node, stack: *std.ArrayList(*const Node)) ?NodeData {
    var mergeResult: ?NodeData = seedNode.data;

    while (stack.items.len > 0) {
        const parent = stack.pop();

        if (mergeResult == null or !mergeResult.?.isComplete()) {
            // We overwrite the data if the parent is a smaller subnet, not a bigger one
            mergeResult = mergeOrSwap(mergeResult, parent.data, false);
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

fn testBits(byte: u8, mask: u8) bool {
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
    const allocator = &std.heap.page_allocator;
    var tree = RadixTree.init(allocator);
    defer {
        tree.destroyNode(tree.head orelse unreachable);
        // TODO:
        // tree.destroy();
    }
    const pfx = try Prefix.fromCidr("1.0.0.0/8");
    const n1 = try tree.insertPrefix(pfx);
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
    const allocator = &std.heap.page_allocator;
    var tree = RadixTree.init(allocator);
    const pfx = try Prefix.fromCidr("1.0.0.0/8");
    const pfx2 = try Prefix.fromCidr("2.0.0.0/8");
    const n1 = try tree.insertPrefix(pfx);
    const n2 = try tree.insertPrefix(pfx2);
    n1.data = .{ .asn = 5 };
    n2.data = .{ .datacenter = true };

    try expect(tree.head != null);
    try expect(tree.numberOfNodes == 3);
}

test "addition or update when adding" {
    const allocator = &std.heap.page_allocator;
    var tree = RadixTree.init(allocator);
    const pfx = try Prefix.fromCidr("1.0.0.0/8");
    const pfx2 = try Prefix.fromCidr("2.0.0.0/8");

    _ = try tree.insertPrefix(pfx);
    _ = try tree.insertPrefix(pfx2);
    _ = try tree.insertPrefix(pfx2);
}

test "should be searchable" {
    const allocator = &std.heap.page_allocator;
    var tree = RadixTree.init(allocator);
    const parent = try Prefix.fromCidr("1.0.0.0/8");
    const node = try tree.insertPrefix(parent);
    node.data = .{ .asn = 5 };

    const pfx = try Prefix.fromCidr("1.1.1.0/32");
    const result = tree.SearchBest(pfx);
    try expect(result != null);
    try expect(result.?.node != null);
    const data = result.?.data.?;
    try expect(data.asn == 5);
    try expect(data.datacenter == null);
}

test "when parent has more data then data should be merged in" {
    const allocator = &std.heap.page_allocator;
    var tree = RadixTree.init(allocator);
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
