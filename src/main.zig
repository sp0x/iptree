const std = @import("std");
const mem = std.mem;
const Prefix = @import("prefix.zig").Prefix;

pub fn main() !void {
    const prefix = try Prefix.fromFamily(std.posix.AF.INET, "192.168.0.0", 24);
    const prefix2 = try Prefix.fromFamily(std.posix.AF.INET, "192.168.0.1", 24);

    std.debug.print("{d} {d}\n", .{ prefix.asNumber(), prefix2.asNumber() });

    // 8:45 - 9:35
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
