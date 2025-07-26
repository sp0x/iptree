const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;
const Address = std.net.Address;

const Prefix = @import("prefix.zig").Prefix;
const RadixTree = @import("radixTree.zig").RadixTree;
const iptree = @import("ipTree.zig");
const NodeData = @import("node.zig").NodeData;
const ASNSource = @import("datasources/asn.zig").ASNSource;
const Datasource = @import("datasources/datasource.zig").Datasource;

pub fn main() !void {
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }

    var dst_tree = iptree.new(alloc);
    var asn = ASNSource{ .base_dir = "data" };
    const sources = [_]Datasource{
        asn.datasource(),
        // Here we'll just add the other sources
    };
    // Go over the dataousrces and if needed fetch them
    for (0..sources.len) |i| {
        var tmpsrc = sources[i];
        try tmpsrc.fetch();
        try tmpsrc.load(&dst_tree, alloc);
    }
    _ = stdout;
    try bw.flush(); // don't forget to flush!
}
