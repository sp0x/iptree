const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;
const Address = std.net.Address;

const Prefix = @import("prefix.zig").Prefix;
const RadixTree = @import("radixTree.zig").RadixTree;
const iptree = @import("ipTree.zig");
const NodeData = @import("node.zig").NodeData;
const ASNSource = @import("datasources/asn.zig").ASNSource;
const UdgerSource = @import("datasources/udger.zig").UdgerSource;
const Datasource = @import("datasources/datasource.zig").Datasource;

pub fn main() !void {
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }

    var dst_tree = iptree.new(arena.allocator());
    var src_asn = ASNSource{ .base_dir = "data" };
    var src_udger = UdgerSource{ .base_dir = "data" };
    const sources = [_]Datasource{
        src_asn.datasource(),
        src_udger.datasource(),
        // Here we'll just add the other sources
    };
    // Go over the dataousrces and if needed fetch them
    for (0..sources.len) |i| {
        var tmpsrc = sources[i];
        try tmpsrc.fetch();
        try tmpsrc.load(&dst_tree, gpa.allocator());
    }
    try stdout.print("Merged tree has {d} nodes\n", .{dst_tree.ipv4.numberOfNodes + dst_tree.ipv6.numberOfNodes});
    var arg_iter = std.process.ArgIterator.init();
    var i: usize = 0;
    while (arg_iter.next()) |arg| {
        i += 1;
        if (i == 1) continue; // skip arg 0 which is the program
        const sr_result = dst_tree.search_best(arg, 32) catch |err| {
            try stdout.print("Search failed: {}\n", .{err});
            return err;
        };
        if (sr_result == null) {
            try stdout.print("No data for {s}\n", .{arg});
            continue;
        }
        const data = sr_result.?.data;

        try stdout.print("{s}/{d}: {?}\n", .{ arg, 32, data });
    }

    try bw.flush(); // don't forget to flush!
}
