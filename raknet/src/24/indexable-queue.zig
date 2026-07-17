const std = @import("std");

const Indexable = @import("utils.zig");

pub fn IndexableQueue(comptime T: type, comptime size: u32, default: T) type {
    comptime {
        if (!std.math.isPowerOfTwo(size))
            @compileError("size must be a power of two for IndexableBufferQueue optimization.");
    }
    return struct {
        pub const RANGE = size;
        pub const RANGE_MASK = RANGE -| 1;
        tail: u32,
        head: u32,
        length: u32,
        buffer: [size]T,

        pub inline fn clear(self: *@This()) void {
            self.tail = self.head;
            self.length = 0;
        }

        /// newIndex inclusive
        /// Asserts new is always greater or equal self.head
        /// Asserts new still fits into free capacity
        pub fn reserve(self: *@This(), new: u32) void {
            const newIndex = Indexable.fixed(new + 1);
            const dist = Indexable.distance(self.head, newIndex);

            std.debug.assert(dist >= 0);
            std.debug.assert(dist <= (RANGE - self.length));

            const headIndex = self.head & RANGE_MASK;
            const endIndex = newIndex & RANGE_MASK;

            if (dist == RANGE)
                @memset(self.buffer, default)
            else if (endIndex < headIndex) {
                @memset(self.buffer[headIndex..RANGE], default);
                @memset(self.buffer[0..endIndex], default);
            } else @memset(self.buffer[headIndex..endIndex], default);

            self.length +%= @bitCast(dist);
            self.head = newIndex;
        }

        pub inline fn setValue(self: *@This(), index: u32, value: T) void {
            std.debug.assert(Indexable.distance(self.tail, index) >= 0);
            std.debug.assert(Indexable.distance(self.head, index) < 0);
            self.buffer[index & RANGE_MASK] = value;
        }

        pub inline fn getValue(self: *const @This(), index: u32) T {
            std.debug.assert(Indexable.distance(self.tail, index) >= 0);
            std.debug.assert(Indexable.distance(self.head, index) < 0);
            return self.buffer[index & RANGE_MASK];
        }

        pub inline fn pop(self: *@This()) T {
            std.debug.assert(self.length > 0);

            const v = self.buffer[self.tail & RANGE_MASK];
            self.tail = Indexable.fixed(self.tail + 1);
            self.length -%= 1;
            return v;
        }
    };
}
