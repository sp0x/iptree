const std = @import("std");
const fs = std.fs;
const print = std.debug.print;
const exec = @import("../process.zig").exec;
const IpTree = @import("../ipTree.zig").IpTree;
const Datasource = @import("./datasource.zig").Datasource;
const utils = @import("../utils.zig");
const ranges = @import("../ranges.zig");
const Prefix = @import("../prefix.zig").Prefix;
const ArrayList = std.ArrayList;

const UDGER_ASSETS_DIR = "tools/udger/";
const FETCH_SCRIPT = "tools/udger/fetch.sh";
const DATA_MAX_STALENESS_DAYS = 7;

fn parse_line(line: []const u8, allocator: std.mem.Allocator, tree: *IpTree) !void {
    if (line[0] == '#' or line[0] == ';') return; // Skip comments
    var line_seq = std.mem.splitSequence(u8, line, "\",\"");
    const datacenter_name = utils.trim_quotes(line_seq.next() orelse return); // Ensure we have a datacenter
    const url = utils.trim_quotes(line_seq.next() orelse return); // Ensure we have a network prefix
    const start_ip_s = utils.trim_quotes(line_seq.next() orelse return); // Ensure we have a start IP
    const end_ip_s = utils.trim_quotes(line_seq.next() orelse return); // Ensure we have an end
    const start_ip = try std.net.Address.parseIp(start_ip_s, 0);
    const end_ip = try std.net.Address.parseIp(end_ip_s, 0);
    if (start_ip.any.family != end_ip.any.family) {
        print("Start and end IP families do not match: {s}, {s}\n", .{ start_ip_s, end_ip_s });
        return;
    }
    const cidrs = try ranges.GetCIDRsInRange(allocator, start_ip.in, end_ip.in);
    defer cidrs.deinit();
    // const desc = utils.trim_quotes(line_seq.next() orelse return); // Ensure we have a description
    _ = url;

    const name = try allocator.dupe(u8, datacenter_name);

    for (cidrs.items) |cidr| {
        const pfx = Prefix.from_ipv4(cidr.network, cidr.cidr);
        print("Inserting datacenter {s} for prefix {}/{}\n", .{ datacenter_name, cidr.network, cidr.cidr });
        try tree.insert_prefix(pfx, .{ .datacenter = true, .name = name });
        // print("Inserted datacenter {s} for prefix {}\n", .{ datacenter_name, cidr });
    }
}

pub const UdgerSource = struct {
    base_dir: []const u8 = "",

    pub fn load(self: *UdgerSource, tree: *IpTree, allocator: std.mem.Allocator) !void {
        const cwd = fs.cwd();
        const tree_allocator = tree.ipv4.allocator;

        const ipv4_file_path = try fs.path.join(allocator, &.{ self.base_dir, "datacenters.csv" });
        defer allocator.free(ipv4_file_path);
        const ipv4_file = cwd.openFile(ipv4_file_path, .{ .mode = .read_only }) catch |err| {
            std.debug.print("Failed to open datacenters file {s}: {any}\n", .{ ipv4_file_path, err });
            return err; // Propagate the error
        };
        defer ipv4_file.close();
        const fsize = try ipv4_file.getEndPos();
        const ipv4_buff = try cwd.readFileAlloc(allocator, ipv4_file_path, fsize);
        defer allocator.free(ipv4_buff);

        var line_iterator = std.mem.splitSequence(u8, ipv4_buff, "\n");
        var line_count: u32 = 0;
        while (line_iterator.next()) |line| {
            // Skip empty lines
            if (line.len == 0) {
                continue;
            } // Parse the line and add it to the tree
            parse_line(line, tree_allocator, tree) catch |err| {
                std.debug.print("Error parsing line: {any}\n", .{line});
                return err; // Propagate the error
            };
            line_count += 1;
        }

        std.debug.print("Udger data loaded successfully from {s}\n", .{ipv4_file_path});
    }

    fn fetch_new_data(self: *UdgerSource) !void {
        // Implement fetching logic if needed
        const allocator = std.heap.page_allocator;
        var build_args = std.ArrayList([]const u8).init(allocator);
        defer build_args.deinit();
        try build_args.appendSlice(&[_][]const u8{ FETCH_SCRIPT, self.base_dir });

        const res = try exec(null, build_args.items, allocator);
        if (res.Exited != 0) {
            print("Failed to fetch datacenters data. Non-zero result: {d}\n", .{res.Exited});
            return error.NotImplemented; // Or handle the error as needed
        }
    }

    pub fn fetch(self: *UdgerSource) !void {
        var dst_dir: fs.Dir = undefined;
        if (self.base_dir.len == 0) {
            // If no base_dir is set, use the current working directory
            dst_dir = fs.cwd();
        } else {
            // If base_dir is set, use it
            dst_dir = fs.cwd().makeOpenPath(self.base_dir, .{}) catch |err| {
                print("Failed to open base directory {s}: {any}\n", .{ self.base_dir, err });
                return err; // Propagate the error
            };
        }
        const n_days = utils.days_since_modification(dst_dir, "datacenters.csv") catch |err| {
            if (err == error.FileNotFound) {
                // If the file does not exist, we should fetch it
                return self.fetch_new_data();
            }
            print("Failed to get modification time for Udger data: {any}\n", .{err});
            return err; // Propagate the error
        };
        if (n_days < DATA_MAX_STALENESS_DAYS) {
            print("Udger data is fresh enough ({} days old), skipping fetch.\n", .{n_days});
            return;
        }

        try self.fetch_new_data();
    }

    pub fn free(_: *UdgerSource) void {
        return;
    }

    pub fn datasource(self: *UdgerSource) Datasource {
        return Datasource.init(self);
    }
};
