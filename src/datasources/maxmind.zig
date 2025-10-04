const std = @import("std");
const fs = std.fs;
const print = std.debug.print;
const exec = @import("../process.zig").exec;
const IpTree = @import("../ipTree.zig").IpTree;
const Datasource = @import("./datasource.zig").Datasource;
const utils = @import("../utils.zig");
const Prefix = @import("../prefix.zig").Prefix;
const Reader = @import("../maxmind/reader.zig").Reader;
const geoip2 = @import("../maxmind/geoip2.zig");

const ASSETS_DIR = "tools/maxmind";
const FETCH_SCRIPT = "tools/maxmind/fetch.sh";
const DATA_MAX_STALENESS_DAYS = 7;
pub const MaxmindSource = struct {
    base_dir: []const u8 = "",
    reader: ?Reader = null,

    pub fn load(self: *MaxmindSource, tree: *IpTree, allocator: std.mem.Allocator) !void {
        // const tree_allocator = tree.ipv4.allocator;
        const mmdb_file_path = try fs.path.join(allocator, &.{ self.base_dir, "mmdb" });
        defer allocator.free(mmdb_file_path);

        var reader = try Reader.map(allocator, mmdb_file_path);
        errdefer reader.unmap();
        self.reader = reader;
        _ = tree;
        print("Maxmind data loaded successfully from {s}\n", .{mmdb_file_path});
        // TODO: load data into the IpTree
    }

    pub fn fetch(self: *MaxmindSource) !void {
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

        const n_days = utils.days_since_modification(dst_dir, "mmdb") catch |err| {
            if (err == error.FileNotFound) {
                // If the file does not exist, we should fetch it
                return utils.exec_fetch(FETCH_SCRIPT, self.base_dir);
            }
            print("Failed to get modification time for maxmind data: {any}\n", .{err});
            return err; // Propagate the error
        };
        if (n_days < DATA_MAX_STALENESS_DAYS) {
            print("Maxmind data is fresh enough ({} days old), skipping fetch.\n", .{n_days});
            return;
        }

        try utils.exec_fetch(FETCH_SCRIPT, self.base_dir);
    }

    pub fn free(_: *MaxmindSource) void {
        return;
    }

    pub fn datasource(self: *MaxmindSource) Datasource {
        return Datasource.init(self);
    }
};
