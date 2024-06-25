const std = @import("std");
const mem = std.mem;
const Prefix = @import("prefix.zig").Prefix;
const RadixTree = @import("radixTree.zig").RadixTree;

pub fn main() !void {
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var tree = RadixTree{};
    const parent = try Prefix.fromCidr("1.0.0.0/8");
    const child = try Prefix.fromCidr("1.0.0.0/16");
    tree.insertPrefix(parent).?.data = .{ .asn = 5 };
    tree.insertPrefix(child).?.data = .{ .datacenter = true };

    const prefixTolookup = try Prefix.fromCidr("1.1.1.0/32");
    const result = tree.searchBest(prefixTolookup) orelse unreachable;

    try stdout.print("Search result {}.\n", .{result});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
