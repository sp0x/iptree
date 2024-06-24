const std = @import("std");
const math = std.math;
const expect = std.testing.expect;
const Prefix = @import("prefix.zig").Prefix;
const Node = @import("node.zig").Node;
const NodeData = @import("node.zig").NodeData;
const newPrefix = @import("prefix.zig").newPrefix;

const maxBits: u8 = 128;

pub const RadixTree = struct {
    head: ?*Node = null,
    numberOfNodes: u32 = 0,

    fn initializeHead(self: *RadixTree, prefix: Prefix) void {
        var newNode = Node{
            .networkBits = prefix.networkBits,
            .prefix = prefix, // try prefix.clone(),
            .parent = null,
            .left = null,
            .right = null,
            .data = undefined,
        };
        self.head = &newNode;
        self.numberOfNodes += 1;
    }

    pub fn insertPrefix(self: *RadixTree, prefix: Prefix, isAddition: *bool) ?*Node {
        if (self.head == null) {
            isAddition.* = true;
            self.initializeHead(prefix);
            return self.head;
        }
        isAddition.* = false;

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
            isAddition.* = false;
            return currentNode;
        }

        var newNode = Node{
            .networkBits = prefix.networkBits,
            .prefix = prefix, // try prefix.clone(),
            .parent = null,
            .left = null,
            .right = null,
            .data = undefined,
        };
        self.numberOfNodes += 1;
        isAddition.* = true;

        if (currentNode.networkBits == differBit) {
            newNode.parent = currentNode;
            const tmpMask: u8 = currentNode.networkBits & 0x07;
            if (currentNode.networkBits < maxBits and testBits(addressBytes[currentNode.networkBits >> 3], math.shr(u8, 0x80, tmpMask))) {
                currentNode.right = &newNode;
            } else {
                currentNode.left = &newNode;
            }
            return &newNode;
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
                self.head = &newNode;
            } else if (currentNode.parent.?.right == currentNode) {
                currentNode.parent.?.right = &newNode;
            } else {
                currentNode.parent.?.left = &newNode;
            }

            currentNode.parent = &newNode;
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
                glueNode.right = &newNode;
                glueNode.left = currentNode;
            } else {
                glueNode.right = currentNode;
                glueNode.left = &newNode;
            }

            newNode.parent = &glueNode;
            if (currentNode.parent == null) {
                self.head = &glueNode;
            } else if (currentNode.parent.?.right == currentNode) {
                currentNode.parent.?.right = &glueNode;
            } else {
                currentNode.parent.?.left = &glueNode;
            }

            currentNode.parent = &glueNode;
        }

        return &newNode;
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

    pub fn searchBest(self: *RadixTree, prefix: Prefix, mergeResult: *?NodeData, collectMergeData: bool) ?*Node {
        var stack = std.ArrayList(*Node).init(std.heap.page_allocator);
        defer stack.deinit();

        var node = self._head;
        if (node == null) return null;

        const address = prefix.ipAddress;
        const bitlen = prefix.networkBits;

        while (node.?.networkBits < bitlen) {
            if (!node.?.prefix.isEmpty) {
                stack.append(node.?) catch return null;
            }

            if (testBits(address[node.?.networkBits >> 3], u8(0x80) >> (node.?.networkBits & 0x07))) {
                node = node.?.right;
            } else {
                node = node.?.left;
            }

            if (node == null) break;
        }

        if (node != null and !node.?.prefix.isEmpty) {
            stack.append(node.?) catch return null;
        }

        while (stack.items.len > 0) {
            node = stack.pop();

            const doPrefixesMatch = compareAddressesWithMask(address, node.?.prefix.ipAddress, node.?.prefix.networkBits);

            if (doPrefixesMatch and node.?.prefix.networkBits <= bitlen) {
                if (collectMergeData) {
                    mergeResult.* = mergeParentStack(node.?, stack);
                }

                return node;
            }
        }

        return null;
    }
};

fn mergeParentStack(leafNode: *Node, stack: *std.ArrayList(*Node)) ?*NodeData {
    var mergeResult: ?*NodeData = leafNode.data;

    while (stack.items.len > 0) {
        const parent = stack.pop();

        if (mergeResult == null or !mergeResult.?.isComplete()) {
            mergeOrSwap(&mergeResult, parent.data, false);
        } else {
            break;
        }
    }

    return mergeResult;
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
    var tree = RadixTree{};
    const pfx = try Prefix.fromFamily(std.posix.AF.INET, "1.0.0.0", 8);
    const pfx2 = try Prefix.fromFamily(std.posix.AF.INET, "2.0.0.0", 8);
    var isAddition: bool = false;
    const n1 = tree.insertPrefix(pfx, &isAddition);
    const n2 = tree.insertPrefix(pfx2, &isAddition);
    n1.?.data = .{ .asn = 5 };
    n2.?.data = .{ .datacenter = true };

    try expect(n1 != null);
    try expect(n2 != null);
    try expect(tree.head != null);
    try expect(tree.numberOfNodes == 3);
}

test "addition or update when adding" {
    var tree = RadixTree{};
    const pfx = try Prefix.fromFamily(std.posix.AF.INET, "1.0.0.0", 8);
    const pfx2 = try Prefix.fromFamily(std.posix.AF.INET, "2.0.0.0", 8);

    var isAddition: bool = false;
    _ = tree.insertPrefix(pfx, &isAddition);
    try expect(isAddition == true);
    _ = tree.insertPrefix(pfx2, &isAddition);
    try expect(isAddition == true);
    _ = tree.insertPrefix(pfx2, &isAddition);
    try expect(isAddition == false);
}
