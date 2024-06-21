const std = @import("std");
const math = std.math;
const expect = std.testing.expect;
const Prefix = @import("prefix.zig").Prefix;
const Node = @import("node.zig").Node;
const newPrefix = @import("prefix.zig").newPrefix;

const maxBits: u8 = 128;

pub const RadixTree = struct {
    head: ?*Node,
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
};

fn testBits(byte: u8, mask: u8) bool {
    return byte & mask == mask;
}

comptime {
    @import("std").testing.refAllDecls(@This());
}

test "construction" {
    var tree = RadixTree{
        .head = null,
        .numberOfNodes = 0,
    };
    const pfx = try Prefix.fromFamily(std.posix.AF.INET, "1.0.0.0", 8);
    const pfx2 = try Prefix.fromFamily(std.posix.AF.INET, "2.0.0.0", 8);
    var isAddition: bool = false;
    const newNode = tree.insertPrefix(pfx, &isAddition);
    const newNode2 = tree.insertPrefix(pfx2, &isAddition);
    std.debug.print("newNode: {}\n", .{tree});
    try expect(newNode != null);
    try expect(newNode2 != null);
    try expect(tree.head != null);
    try expect(tree.numberOfNodes == 3);
}
