const std = @import("std");

const Index24 = @import("utils.zig");

pub fn IndexableBitQueue(comptime range: comptime_int) type {
    comptime {
        if (!std.math.isPowerOfTwo(range))
            @compileError("UNACKNOWLEDGED_WINDOWS_SIZE must be a power of two for BitRingBuffer optimization.");
    }
    const BitSet = std.bit_set.ArrayBitSet(usize, range);
    return struct {
        const Indexable = @This();
        pub const RANGE = range;
        pub const RANGE_MASK = RANGE -| 1;
        head: u32 = 0,
        tail: u32 = 0,
        capacity: u32 = RANGE,
        buffer: BitSet = .empty,

        pub inline fn clear(self: *Indexable) void {
            self.tail = self.head;
            self.capacity = RANGE;
        }

        /// Iterator could be invalidated if BitRingBuffer is changed
        pub inline fn iterator(self: *const Indexable) IndexableBitQueueIterator {
            return .{
                .index = self.tail,
                .remaining = RANGE -% self.capacity,
                .ref = self,
            };
        }

        /// newIndex inclusive
        /// Asserts new is always greater or equal self.head
        /// Asserts new still fits into free self.capacity
        pub fn reserve(self: *Indexable, new: u32) void {
            const newIndex = Index24.fixed(new + 1);
            const dist = Index24.distance(self.head, newIndex);

            std.debug.assert(dist >= 0);
            std.debug.assert(dist <= self.capacity);

            const headIndex = self.head & RANGE_MASK;
            const endIndex = newIndex & RANGE_MASK;

            if (endIndex < headIndex) {
                self.buffer.setRangeValue(.{ .start = headIndex, .end = RANGE }, false);
                self.buffer.setRangeValue(.{ .start = 0, .end = endIndex }, false);
            } else {
                self.buffer.setRangeValue(.{ .start = headIndex, .end = endIndex }, false);
            }

            self.capacity -= @bitCast(dist);
            self.head = newIndex;
        }

        pub inline fn setValue(self: *Indexable, index: u32, value: bool) void {
            std.debug.assert(Index24.distance(self.tail, index) >= 0);
            std.debug.assert(Index24.distance(self.head, index) < 0);
            self.buffer.setValue(index & RANGE_MASK, value);
        }

        pub inline fn getValue(self: *const Indexable, index: u32) bool {
            std.debug.assert(Index24.distance(self.tail, index) >= 0);
            std.debug.assert(Index24.distance(self.head, index) < 0);
            return self.buffer.isSet(index & RANGE_MASK);
        }

        /// if head is smaller than tail it means it overflowed
        pub const RangeBit = struct {
            tail: u32,
            head: u32,
            bit: bool,
        };

        const IndexableBitQueueIterator = struct {
            index: u32,
            remaining: u32,
            ref: *const Indexable,
            pub fn next(self: *IndexableBitQueueIterator) ?RangeBit {
                const remains = self.remaining;
                if (remains == 0) return null;

                const start = self.index;
                const value = self.ref.getValue(self.index);
                while (self.remaining > 0 and self.ref.getValue(self.index) == value) {
                    self.remaining -%= 1;
                    self.index = Index24.fixed(self.index +% 1);
                }

                if (remains == self.remaining) return null;
                return .{
                    .tail = start,
                    .head = self.index,
                    .bit = value,
                };
            }
        };
    };
}

test "Overflow Level 1" {
    const BitRingBufferDefault = IndexableBitQueue(512);
    var ring: BitRingBufferDefault = .{ .buffer = .empty, .tail = 412, .head = 412, .capacity = BitRingBufferDefault.RANGE };
    try std.testing.expectEqual(BitRingBufferDefault.RANGE, ring.capacity);

    ring.reserve(ring.head);
    try std.testing.expectEqual(BitRingBufferDefault.RANGE - 1, ring.capacity);

    ring.clear();
    try std.testing.expectEqual(BitRingBufferDefault.RANGE, ring.capacity);

    ring.reserve(ring.head + BitRingBufferDefault.RANGE - 1);
    try std.testing.expectEqual(0, ring.capacity);

    ring.setValue(ring.tail, true);
    try std.testing.expectEqual(true, ring.getValue(ring.tail));
}

test "Overflow Level 2" {
    const BitRingBufferDefault = IndexableBitQueue(512);
    var ring: BitRingBufferDefault = .{ .buffer = .empty, .tail = 0xFF_FFFE, .head = 0xFF_FFFE, .capacity = BitRingBufferDefault.RANGE };
    try std.testing.expectEqual(BitRingBufferDefault.RANGE, ring.capacity);

    ring.reserve(ring.head);
    try std.testing.expectEqual(BitRingBufferDefault.RANGE - 1, ring.capacity);

    ring.clear();
    try std.testing.expectEqual(BitRingBufferDefault.RANGE, ring.capacity);
    try std.testing.expectEqual(ring.head, 0xFFFFFF);

    ring.reserve(ring.head + BitRingBufferDefault.RANGE - 1);
    try std.testing.expectEqual(0, ring.capacity);

    ring.setValue(ring.tail, true);
    try std.testing.expectEqual(true, ring.getValue(ring.tail));
    ring.setValue(ring.tail, false);
    try std.testing.expectEqual(false, ring.getValue(ring.tail));

    try std.testing.expect(ring.head < 0xFFFFFF);

    // Special case of overflow allocation
    ring = .{ .buffer = .empty, .tail = 0xFFFFFF, .head = 0xFFFFFF, .capacity = BitRingBufferDefault.RANGE };
    try std.testing.expectEqual(BitRingBufferDefault.RANGE, ring.capacity);

    ring.reserve(0);
    try std.testing.expectEqual(BitRingBufferDefault.RANGE - 2, ring.capacity);

    var ite = ring.iterator();
    const value = ite.next();

    try std.testing.expect(value != null);

    // false means this range is range of zeros
    try std.testing.expectEqual(false, value.?.bit);

    // bc of overflow, the tail is still big but head small
    try std.testing.expectEqual(2, Index24.distance(value.?.tail, value.?.head));
}
