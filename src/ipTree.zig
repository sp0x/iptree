const rxTree = @import("radixTree.zig");
const RadixTree = rxTree.RadixTree;
const SearchResult = rxTree.SearchResult;
const Prefix = @import("prefix.zig").Prefix;
const NodeData = @import("node.zig").NodeData;
const std = @import("std");
const posix = std.posix;

pub const IpTree = struct {
    ipv4: RadixTree = RadixTree{},
    ipv6: RadixTree = RadixTree{},

    pub fn insert(self: *IpTree, addr: []const u8, mask: u8, value: ?NodeData) !void {
        const prefix = try Prefix.fromIpAndMask(addr, mask);
        var tree = try self.pickTree(prefix.family);
        const node = tree.insertPrefix(prefix) orelse return error.CouldNotInsert;

        node.*.data = value;
    }

    pub fn searchBest(self: *IpTree, addr: []const u8, mask: u8) !?SearchResult {
        const prefix = try Prefix.fromIpAndMask(addr, mask);
        const tree = try self.pickTree(prefix.family);
        return tree.searchBest(prefix);
    }

    fn pickTree(self: *IpTree, family: u8) !*RadixTree {
        return switch (family) {
            posix.AF.INET => return &self.ipv4,
            posix.AF.INET6 => return &self.ipv6,
            else => return error.UnsupportedFamily,
        };
    }
};

test "insert" {
    var tree = IpTree{};
    const addr = "1.1.1.1";
    const mask = 32;
    const value = NodeData{ .asn = 1 };

    try tree.insert(addr, mask, value);
}
