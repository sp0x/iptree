const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const print = std.debug.print;
const mem = std.mem;
const Allocator = std.mem.Allocator;

fn getPathFromFd(fd: std.fs.File.Handle) ![]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var buf_path: [std.fs.max_path_bytes]u8 = undefined;
    const proc_path = try std.fmt.bufPrint(&buf, "/proc/self/fd/{}", .{fd});
    return try std.fs.readLinkAbsolute(proc_path, &buf_path);
}

pub fn map(f: std.fs.File) ![]u8 {
    // TODO: We probably need CreateFileMapping, MapViewOfFile to support Windows,
    // see https://github.com/ziglang/zig/pull/21083.

    const fstat = try f.stat();
    const file_size = fstat.size;
    const page_size = std.heap.pageSize();
    const aligned_file_size = mem.alignForward(usize, file_size, page_size);
    const src = try posix.mmap(
        null,
        aligned_file_size,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        f.handle,
        0,
    );

    return src;
}

pub fn unmap(src: []u8) void {
    const page_size = std.heap.pageSize();
    const aligned_src_len = mem.alignForward(usize, src.len, page_size);
    std.posix.munmap(@alignCast(src.ptr[0..aligned_src_len]));
}

/// Remap a memory-mapped region to a new size.
/// The returned slice may have a different pointer than the input slice.
/// The contents of the original slice up to the minimum of the old and new sizes are preserved.
/// If the new size is larger than the old size, the additional memory is uninitialized.
pub fn mremap(
    old_ptr: []u8,
    new_size: usize,
) ![]u8 {
    const page_size = std.heap.pageSize();
    const aligned_src_len = mem.alignForward(usize, old_ptr.len, page_size);
    const aligned_new_size = mem.alignForward(usize, new_size, page_size);
    // https://man7.org/linux/man-pages/man2/mremap.2.html
    const src = try posix.mremap(
        @alignCast(old_ptr.ptr),
        aligned_src_len,
        aligned_new_size,
        .{ .MAYMOVE = true }, // MAYMOVE is the default on Linux
        null,
    );

    return src;
}

/// Resizes the file to a new size and remaps the memory-mapped region to the file with the new size. New segment does not contain any data.
pub fn remap_and_resize(
    f: std.fs.File,
    old_ptr: []u8,
    new_size: usize,
) ![]u8 {
    // FAllocate, so the file is bigger
    // https://github.com/ziglang/zig/blob/f58200e3f2967a06f343c9fc9dcae9de18def92a/src/link/MappedFile.zig#L574
    const initial_size: i64 = @intCast(old_ptr.len);
    const len: i64 = @as(i64, @intCast(new_size)) - initial_size;
    const ret = linux.fallocate(f.handle, linux.FALLOC.FL_ZERO_RANGE, initial_size, len);
    switch (linux.E.init(ret)) {
        .SUCCESS => {},
        else => return error.FallocateFailed,
    }

    return mremap(old_ptr, new_size);
}

test "remap_and_resize" {
    const initial_size: usize = 4096;
    const new_size: usize = 8192;
    const temp_dir = std.testing.tmpDir(.{});
    var random_bytes: [initial_size]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);

    const file_path = "testfile.bin";
    const file = try temp_dir.dir.createFile(file_path, .{ .read = true });
    defer file.close();
    try file.writeAll(&random_bytes);

    var mapped = try map(file);

    // Write some data to the mapped region
    std.crypto.random.bytes(mapped);
    @memcpy(mapped[0..13], "Hello, World!");
    // FAllocate, so the file is bigger
    // https://github.com/ziglang/zig/blob/f58200e3f2967a06f343c9fc9dcae9de18def92a/src/link/MappedFile.zig#L574
    mapped = try remap_and_resize(file, mapped, new_size);
    // Verify that the original data is still intact
    try expect(std.mem.eql(u8, mapped[0..13], "Hello, World!"));
    @memcpy(mapped[initial_size .. initial_size + 1], "a"); // Clear the new region for testing

    // Write additional data to the new region
    for (mapped[initial_size..new_size], 0..) |*b, i| {
        b.* = @as(u8, @intCast((i + initial_size) % 256));
    }

    // Verify the new data
    for (mapped[initial_size..new_size], 0..) |b, i| {
        try std.testing.expect(b == @as(u8, @intCast((i + initial_size) % 256)));
    }
}
