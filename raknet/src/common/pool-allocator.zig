const std = @import("std");

pub const POOL_SIZE = @import("../core/well-known.zig").MAX_MTU_FRAME_SIZE;

const Pool = std.heap.MemoryPoolExtra(
    [POOL_SIZE]u8,
    .{
        .alignment = .of(usize),
        .growable = true,
    },
);

backing_allocator: std.mem.Allocator,
pool: Pool,

pub fn init(allocator: std.mem.Allocator) !@This() {
    return .{
        .backing_allocator = allocator,
        .pool = (try Pool.initCapacity(allocator, 64)),
    };
}

pub inline fn deinit(self: *@This()) void {
    self.pool.deinit(self.backing_allocator);
}

pub inline fn create(self: *@This(), comptime T: type) !*T {
    if (@sizeOf(T) > POOL_SIZE)
        @compileError("Object too large, T:" ++ @typeName(T));
    if (@alignOf(T) > @alignOf(usize))
        @compileError("Alignment too large for " ++ @typeName(T));

    const ptr = try self.pool.create(self.backing_allocator);
    return @ptrCast(@alignCast(ptr));
}

pub inline fn remaining(_: *const @This(), comptime T: type, value: *T) []u8 {
    if (@sizeOf(T) > POOL_SIZE)
        @compileError("Object too large, T:" ++ @typeName(T));

    const ptr: [*]u8 = @ptrCast(value);
    return ptr[@sizeOf(T)..POOL_SIZE];
}

pub inline fn destroy(self: *@This(), v: *anyopaque) void {
    const block_ptr: *[POOL_SIZE]u8 = @ptrCast(@alignCast(v));
    self.pool.destroy(block_ptr);
}
