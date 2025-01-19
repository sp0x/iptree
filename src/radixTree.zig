const std = @import("std");
const mem = std.mem;
const math = std.math;
const expect = std.testing.expect;
const Prefix = @import("prefix.zig").Prefix;
const Node = @import("node.zig").Node;
const NodeData = @import("node.zig").NodeData;

const maxBits: u8 = 128;

pub const SearchResult = struct { node: ?*Node, data: ?NodeData };
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

    pub fn searchBest(self: *RadixTree, prefix: Prefix) ?SearchResult {
        if (self.head == null) {
            return null;
        }

        var stack = std.ArrayList(*Node).init(std.heap.page_allocator);
        defer stack.deinit();
        var node: ?*Node = self.head.?;

        const addressBytes = prefix.asBytes();
        const bitlen = prefix.networkBits;
        while (node.?.networkBits < bitlen) {
            const snode = node.?.*;
            if (!snode.prefix.isEmpty()) {
                stack.append(node orelse unreachable) catch return null;
            }

            if (testBits(addressBytes[snode.networkBits >> 3], math.shr(u8, 0x80, snode.networkBits & 0x07))) {
                // Possible issue here!
                node = snode.right;
            } else {
                // Or here
                node = snode.left;
            }

            if (node == null) break;
        }

        if (node != null and !node.?.prefix.isEmpty()) {
            stack.append(node.?) catch return null;
        }

        std.debug.print("Tree: {}\n", .{self});
        while (stack.items.len > 0) {
            const snode = stack.pop();
            const nodeAddrBytes = snode.prefix.asBytes();

            const doPrefixesMatch = compareAddressesWithMask(addressBytes, nodeAddrBytes, snode.prefix.networkBits);

            if (doPrefixesMatch and snode.prefix.networkBits <= bitlen) {
                const mergeResult = mergeParentStack(snode, &stack);

                return .{
                    .node = snode,
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

fn mergeParentStack(leafNode: *Node, stack: *std.ArrayList(*Node)) ?NodeData {
    var mergeResult: ?NodeData = leafNode.data;

    while (stack.items.len > 0) {
        const parent = stack.pop();

        if (mergeResult == null or !mergeResult.?.isComplete()) {
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
    return dest;
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

inline fn getDigits(num: u32) u32 {
    var digits: u32 = 0;
    var n = num;
    while (n != 0) {
        n /= 10;
        digits += 1;
    }
    return digits;
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
    std.debug.print("{}\n", .{pfx});
    const result = tree.searchBest(pfx);
    try expect(result != null);
}

test "when parent has more data then data should be merged in" {
    const allocator = &std.heap.page_allocator;
    var tree = RadixTree.init(allocator);
    const parent = try Prefix.fromCidr("1.0.0.0/8");
    const child = try Prefix.fromCidr("1.1.0.0/16");
    try tree.insertValue(parent, .{ .asn = 5 });
    try tree.insertValue(child, .{ .datacenter = true });

    const pfx = try Prefix.fromCidr("1.1.1.0/32");

    const result = tree.searchBest(pfx);

    std.debug.print("Result: {}\n", .{result.?.data.?});
    try expect(result != null);
    try expect(result.?.node != null);
    const data = result.?.data.?;
    try expect(data.asn == 5);
    try expect(data.datacenter == true);
}
