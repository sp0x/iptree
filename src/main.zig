const std = @import("std");
const mem = std.mem;
const Address = std.net.Address;

const Prefix = @import("prefix.zig").Prefix;
const RadixTree = @import("radixTree.zig").RadixTree;
const IpTree = @import("ipTree.zig").IpTree;
const NodeData = @import("node.zig").NodeData;

pub fn main() !void {
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    _ = stdout;
    try bw.flush(); // don't forget to flush!
}
