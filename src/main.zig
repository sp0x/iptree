const std = @import("std");
const mem = std.mem;
const Address = std.net.Address;

const Prefix = @import("prefix.zig").Prefix;
const RadixTree = @import("radixTree.zig").RadixTree;
const IpTree = @import("ipTree.zig").IpTree;
const NodeData = @import("node.zig").NodeData;
const Utils = @import("utils.zig");

pub fn main() !void {
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const allocator = std.heap.page_allocator;
    // 51.4.0.0-51.5.255.255 -> 51.4.0.0:0/15
    const start_ip = Address.parseIp("51.4.0.0", 0) catch unreachable;
    const end_ip = Address.parseIp("51.5.255.255", 0) catch unreachable;
    const ranges: [2][]const u8 = [2][]const u8{ &[_]u8{ 0x33, 0x4, 0x0, 0x0 }, &[_]u8{ 0x33, 0x5, 0xff, 0xff } };
    const bits = Utils.get_min_network_bits(ranges[0], ranges[1]);

    try stdout.print("Min network bits: {d}", .{bits});

    const results = try Utils.GetNetworkAndCidrFromIps(allocator, start_ip, end_ip);
    for (results.items) |result| {
        std.debug.print("Network: {}\n", .{result});
    }

    var tree = RadixTree{};
    const parent = try Prefix.fromCidr("1.0.0.0/8");
    const child = try Prefix.fromCidr("1.1.0.0/16");

    try tree.insertValue(parent, .{ .asn = 5 });
    try tree.insertValue(child, .{ .datacenter = true });

    const pfx = try Prefix.fromCidr("1.1.1.0/32");
    std.debug.print("{}\n", .{pfx});
    const result = tree.searchBest(pfx) orelse {
        _ = try bw.write("No search result found.\n");
        return;
    };

    try stdout.print("\nSearch result {}.\n", .{result.data.?});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
