const std = @import("std");
const assert = std.debug.assert;
const fs = std.fs;
const net = std.net;
const posix = std.posix;
const RadixTree = @import("../radixTree.zig").RadixTree;
const exec = @import("../process.zig").exec;
const IpTree = @import("../ipTree.zig").IpTree;
const Datasource = @import("./datasource.zig").Datasource;
const Allocator = std.mem.Allocator;
const ChildProcess = std.process.Child;

pub const Errors = error{
    NotImplemented,
    UnsupportedFamily,
};

const ASN_ASSETS_DIR = "tools/asn/";
const FETCH_SCRIPT = "tools/asn/fetch.sh";

pub const ASNSource = struct {
    file_path: []const u8,

    pub fn load(self: *ASNSource, tree: *IpTree, allocator: Allocator) !void {

        // ... load ASN data from asn_self.file_path into tree ...
        _ = tree;
        _ = allocator;
        // Your loading logic here
        std.debug.print("Loading ASN datasource from {s}\n", .{self.file_path});
    }

    pub fn free(_: *ASNSource) void {}

    /// Fetches the resources in ./dataset_asn
    pub fn fetch(_: *ASNSource) !void {
        // Define the Bash interpreter and script to run

        // Spawn the Bash process
        const allocator = std.heap.page_allocator;
        var build_args = std.ArrayList([]const u8).init(allocator);
        defer build_args.deinit();
        const cwd = fs.cwd();
        const cwdPath = try cwd.realpathAlloc(allocator, "./");
        defer allocator.free(cwdPath);
        const dataPath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cwdPath, "data" });
        defer allocator.free(dataPath);

        try build_args.appendSlice(&[_][]const u8{ FETCH_SCRIPT, dataPath });

        const res = try exec(cwdPath, build_args.items, allocator);
        std.debug.print("{}\n", .{res});
    }

    pub fn datasource(self: *ASNSource) Datasource {
        return Datasource.init(self);
        // return .{
        //     .ptr = self,
        //     .vtable = &.{
        //         .load = ASNSource.load,
        //         .free = null, // No free function for now
        //         .fetch = ASNSource.fetch,
        //     },
        // };
    }
};

test "asn source construction" {
    const allocator = std.heap.page_allocator;
    const asn_source = ASNSource{ .file_path = "/tmp" };
    const tree = RadixTree.init(allocator);
    try asn_source.base.load(&asn_source.base, &tree, allocator);
    try asn_source.base.fetch(&asn_source.base);
    // Add more tests as needed
}
