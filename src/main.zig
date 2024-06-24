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
    const pfx = try Prefix.fromFamily(std.posix.AF.INET, "1.0.0.0", 8);
    const pfx2 = try Prefix.fromFamily(std.posix.AF.INET, "2.0.0.0", 8);
    var isAddition: bool = false;
    var n1 = tree.insertPrefix(pfx, &isAddition);
    var n2 = tree.insertPrefix(pfx2, &isAddition);
    n1.?.data = .{ .asn = 5 };
    n2.?.data = .{ .datacenter = true };

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
