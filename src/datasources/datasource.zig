//! The standard memory allocation interface.

const std = @import("std");
const Allocator = std.mem.Allocator;
const RadixTree = @import("../radixTree.zig").RadixTree;
const IpTree = @import("../ipTree.zig").IpTree;

pub const Datasource = struct {
    ptr: *anyopaque,

    /// Function pointer to load data into the tree
    loadFn: *const fn (self: *anyopaque, tree: *IpTree, allocator: Allocator) anyerror!void,

    /// Optional: function pointer to free any resources
    freeFn: *const fn (self: *anyopaque) void,

    fetchFn: *const fn (self: *anyopaque) anyerror!void,

    pub fn load(self: *Datasource, tree: *IpTree, allocator: std.mem.Allocator) !void {
        return self.loadFn(self.ptr, tree, allocator);
    }

    pub fn init(lp: anytype) Datasource {
        const T = @TypeOf(lp);
        const ptr_info = @typeInfo(T);
        if (ptr_info != .Pointer) @compileError("ptr must be a pointer");
        if (ptr_info.Pointer.size != .One) @compileError("ptr must be a single item pointer");

        const gen = struct {
            pub fn load(p: *anyopaque, tree: *IpTree, allocator: Allocator) anyerror!void {
                const self: T = @ptrCast(@alignCast(p));
                // child is the actual type of the pointer
                return ptr_info.Pointer.child.load(self, tree, allocator);
            }
            pub fn fetch(p: *anyopaque) !void {
                const self: T = @ptrCast(@alignCast(p));
                // child is the actual type of the pointer
                try ptr_info.Pointer.child.fetch(self);
            }
            pub fn free(p: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(p));
                // child is the actual type of the pointer
                ptr_info.Pointer.child.free(self);
            }
        };

        return .{
            .ptr = lp,
            .loadFn = gen.load,
            .freeFn = gen.free, // No free function for now
            .fetchFn = gen.fetch,
        };
    }
};
