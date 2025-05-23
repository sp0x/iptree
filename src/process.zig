const std = @import("std");
const io = std.io;
const assert = std.debug.assert;
const fs = std.fs;
const net = std.net;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const ChildProcess = std.process.Child;

// TODO: Add a function to make the polling and copying from the child process to the parent process
//

const proc_streams = struct {
    buff_stdout: io.BufferedWriter(4096, fs.File.Writer),
    buff_stderr: io.BufferedWriter(4096, fs.File.Writer),

    // fn stdout(self: *proc_streams) std.io.Writer {
    //     return self.buff_stdout.writer();
    // }

    // fn stderr(self: *proc_streams) std.io.Writer {
    //     return self.buff_stderr.writer();
    // }
    fn writeAll(self: *proc_streams, slice: []const u8) !void {
        var dest = self.buff_stdout.writer();
        try dest.writeAll(slice);
    }

    /// Write to stderr
    fn errWriteAll(self: *proc_streams, slice: []const u8) !void {
        var dest = self.buff_stderr.writer();
        try dest.writeAll(slice);
    }

    fn flush(self: *proc_streams) !void {
        try self.buff_stdout.flush();
    }

    fn flusherr(self: *proc_streams) !void {
        try self.buff_stderr.flush();
    }

    fn flushall(self: *proc_streams) !void {
        self.buff_stdout.flush() catch |err| {
            std.debug.print("Error flushing stdout: {}\n", .{err});
            return err;
        };
        self.buff_stderr.flush() catch |err| {
            std.debug.print("Error flushing stderr: {}\n", .{err});
            return err;
        };
    }
};

fn get_proc_streams() !proc_streams {
    const stdout_file = std.io.getStdOut().writer();
    const stderr_file = std.io.getStdErr().writer();
    return .{
        .buff_stdout = std.io.bufferedWriter(stdout_file),
        .buff_stderr = std.io.bufferedWriter(stderr_file),
    };
}

pub fn exec(cwd: []const u8, argv: []const []const u8, allocator: Allocator) !ChildProcess.Term {
    var streams = try get_proc_streams();
    defer streams.flushall() catch |err| {
        std.debug.print("Error flushing streams: {}\n", .{err});
    };

    std.debug.print("Executing command: {s}\n", .{argv});

    var child = ChildProcess.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = cwd;
    child.env_map = null;
    child.spawn() catch |err| {
        std.debug.print("The following command failed:\n", .{});
        printCmd(cwd, argv);
        std.debug.print("Error: {}\n", .{err});
        return err;
    };
    // Pipe the process's stdout and stderr to the parent process
    var poller = std.io.poll(allocator, enum { stdoutx, stderrx }, .{
        .stdoutx = child.stdout.?,
        .stderrx = child.stderr.?,
    });
    defer poller.deinit();

    while (try poller.poll()) {
        const stdpinfo = poller.fifo(.stdoutx);
        const stderrfifo = poller.fifo(.stderrx);
        const len_stdout = stdpinfo.readableLength();
        const len_stderr = stderrfifo.readableLength();
        if (len_stdout != 0) {
            const slice = stdpinfo.readableSlice(0);
            assert(slice.len == len_stdout);
            try streams.writeAll(slice);
            try streams.flush();
            stdpinfo.discard(len_stdout);
        }

        if (len_stderr != 0) {
            const slice = stderrfifo.readableSlice(0);
            assert(slice.len == len_stderr);
            try streams.errWriteAll(slice);
            try streams.flusherr();
            stderrfifo.discard(len_stderr);
        }
    }

    // Wait for the child process to finish closing down the pipes
    // and to free the resources
    return child.wait() catch |err| {
        std.debug.print("Waiting command failed:\n", .{});
        printCmd(cwd, argv);
        std.debug.print("Error: {}\n", .{err});
        return err;
    };
}

fn printCmd(cwd: []const u8, argv: []const []const u8) void {
    std.debug.print("cd {s} && ", .{cwd});
    for (argv) |arg| {
        std.debug.print("{s} ", .{arg});
    }
    std.debug.print("\n", .{});
}
