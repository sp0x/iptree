const std = @import("std");
const fs = std.fs;
const math = std.math;

pub fn days_since_modification(dataset_dir: fs.Dir, descriptor: []const u8) !u64 {
    const modification_tsec = try last_modified(dataset_dir, descriptor);
    const now = std.time.timestamp();
    const delta_ms: i128 = now - modification_tsec;
    // The modification date MUST be in the past
    std.debug.assert(delta_ms >= 0);
    const days = @divTrunc(delta_ms, std.time.ns_per_day);
    return @bitCast(math.lossyCast(i64, days));
}

pub fn last_modified(dataset_dir: fs.Dir, descriptor: []const u8) !i64 {
    const ipv4_data_file = dataset_dir.openFile(descriptor, .{ .mode = .read_only }) catch |err| {
        if (err == error.FileNotFound) {
            return 0;
        }
        return err;
    };
    defer ipv4_data_file.close();
    const ipv4_meta = try ipv4_data_file.metadata();
    const ipv4_ts_nano = ipv4_meta.modified();

    return math.lossyCast(i64, @divTrunc(ipv4_ts_nano, std.time.ns_per_s));
}
