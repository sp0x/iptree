const std = @import("std");
const math = std.math;
const time = std.time;
const assert = std.debug.assert;
const fs = std.fs;
const net = std.net;
const posix = std.posix;
const RadixTree = @import("../radixTree.zig").RadixTree;
const utils = @import("../utils.zig");
const exec = @import("../process.zig").exec;
const IpTree = @import("../ipTree.zig").IpTree;
const Datasource = @import("./datasource.zig").Datasource;
const Allocator = std.mem.Allocator;
const ChildProcess = std.process.Child;
const print = std.debug.print;

pub const Errors = error{
    NotImplemented,
    UnsupportedFamily,
};

const ASN_ASSETS_DIR = "tools/asn/";
const FETCH_SCRIPT = "tools/asn/fetch.sh";
const DATA_MAX_STALENESS_DAYS = 7;

fn parse_line(line: []const u8, tree: *IpTree) !void {
    if (line[0] == '#' or line[0] == ';') return; // Skip comments
    print("Parsing line: {s}\n", .{line});
    var line_seq = std.mem.splitSequence(u8, line, "\t");

    // Parse the ASN and IP prefix
    const net_cidr = line_seq.next() orelse return; // Ensure we have a network prefix
    var prefix_parts = std.mem.splitSequence(u8, net_cidr, "/");
    const ip = prefix_parts.next() orelse return; // Ensure we have an IP prefix
    const mask_str = prefix_parts.next() orelse return; // Ensure we have a mask
    const mask = std.fmt.parseInt(u8, mask_str, 10) catch |err| {
        print("Failed to parse mask: {any}: {any}\n", .{ mask_str, err });
        return;
    };
    const asn_str = line_seq.next() orelse return; // Ensure we have an ASN
    const asn: u32 = std.fmt.parseInt(u32, asn_str, 10) catch |err| {
        print("Failed to parse ASN: {any}: {any}\n", .{ asn_str, err });
        return;
    };
    print("Inserting IP: {s}, Mask: {d}, ASN: {d}\n", .{ ip, mask, asn });
    // Insert into the tree
    try tree.insert(ip, mask, .{
        .asn = asn,
    });
}

pub const ASNSource = struct {
    // The base directory for the ASN data
    base_dir: []const u8,

    pub fn load(self: *ASNSource, tree: *IpTree, allocator: Allocator) !void {
        const cwd = fs.cwd();
        const ipv4_file_path = try fs.path.join(allocator, &.{ self.base_dir, "rib.dat" });
        defer allocator.free(ipv4_file_path);
        const ipv4_file = cwd.openFile(ipv4_file_path, .{ .mode = .read_only }) catch |err| {
            print("Failed to open ASN file {s}: {any}\n", .{ ipv4_file_path, err });
            return err; // Propagate the error
        };
        defer ipv4_file.close();
        const fsize = try ipv4_file.getEndPos();

        const ipv4_buff = try cwd.readFileAlloc(allocator, ipv4_file_path, fsize);
        defer allocator.free(ipv4_buff);
        var line_iterator = std.mem.splitSequence(u8, ipv4_buff, "\n");
        while (line_iterator.next()) |line| {
            // Skip empty lines
            if (line.len == 0) {
                print("Skipping empty line\n", .{});
                continue;
            } // Parse the line and add it to the tree
            parse_line(line, tree) catch |err| {
                print("Error parsing line: {any}\n", .{line});
                return err; // Propagate the error
            };
        }

        print("ASN data loaded successfully from {s}\n", .{ipv4_file_path});
    }

    pub fn free(_: *ASNSource) void {}

    fn fetch_new_data(self: *ASNSource) !void {
        const allocator = std.heap.page_allocator;
        var build_args = std.ArrayList([]const u8).init(allocator);
        defer build_args.deinit();
        try build_args.appendSlice(&[_][]const u8{ FETCH_SCRIPT, self.base_dir });

        const res = try exec(null, build_args.items, allocator);
        print("ASN Fetching result:\n{}\n", .{res});
    }

    /// Fetches the resources in ./dataset_asn
    pub fn fetch(self: *ASNSource) !void {
        const dst_dir = try fs.cwd().makeOpenPath(self.base_dir, .{});

        const n_days = utils.days_since_modification(dst_dir, "rib.dat") catch |err| {
            if (err == error.FileNotFound) {
                // If the file does not exist, we should fetch it
                return self.fetch_new_data();
            }
            print("Failed to get modification time for ASN data: {any}\n", .{err});
            return err; // Propagate the error
        };
        if (n_days < DATA_MAX_STALENESS_DAYS) {
            print("ASN data is fresh enough ({} days old), skipping fetch.\n", .{n_days});
            return;
        }

        try self.fetch_new_data();
    }

    pub fn datasource(self: *ASNSource) Datasource {
        return Datasource.init(self);
    }
};

test "asn source construction" {
    const allocator = std.heap.page_allocator;
    const asn_source = ASNSource{ .base_dir = "/tmp" };
    const tree = RadixTree.init(allocator);
    try asn_source.base.load(&asn_source.base, &tree, allocator);
    try asn_source.base.fetch(&asn_source.base);
    // Add more tests as needed
} //
