const std = @import("std");

const well_known = @import("../core/well-known.zig");
pub const RANGE = well_known.UNACKNOWLEDGED_WINDOWS_SIZE;
const Index24Utils = @import("./index-24-utils.zig");

const BitSet = std.bit_set.ArrayBitSet(usize, well_known.UNACKNOWLEDGED_WINDOWS_SIZE);

const BitRingBuffer = @This();
head: u32 = 0,
tail: u32 = 0,
capacity: u32 = RANGE,
buffer: BitSet = .empty,

pub inline fn clear(self: *BitRingBuffer) void {
    self.tail = self.head;
    self.capacity = RANGE;
}

pub inline fn iterator(self: *const BitRingBuffer) BitRingBufferIterator {
    return .{
        .cursor = self.tail,
        .ref = self,
    };
}

pub inline fn getHead(self: *const BitRingBuffer) u32 {
    return Index24Utils.cover(self.head, self.tail > self.head);
}

/// newIndex inclusive
/// Asserts newIndex can extend without overflowing capacity
/// Asserts newIndex is larger or equal to head it self
pub inline fn reserve(self: *BitRingBuffer, new: u32) void {
    const newIndex = new + 1;
    std.debug.assert(Index24Utils.getDistance(self.head, newIndex) >= 0);
    std.debug.assert(Index24Utils.getDistance(self.head, newIndex) <= self.capacity);

    const headIndex = self.head % RANGE;
    const tailIndex = self.tail % RANGE;
    const endIndex = newIndex % RANGE;
    if (endIndex < headIndex) {
        self.buffer.setRangeValue(.{ .start = headIndex, .end = RANGE }, false);
        self.buffer.setRangeValue(.{ .start = 0, .end = endIndex }, false);
    } else {
        self.buffer.setRangeValue(.{ .start = headIndex, .end = endIndex }, false);
    }
    if (endIndex <= tailIndex)
        self.capacity = (tailIndex - endIndex)
    else
        self.capacity = RANGE - (endIndex - tailIndex);
    self.head = Index24Utils.fix(newIndex);
}

pub inline fn setValue(self: *BitRingBuffer, index: u32, value: bool) void {
    std.debug.assert(Index24Utils.getDistance(self.tail, index) >= 0);
    std.debug.assert(Index24Utils.getDistance(self.head, index) < 0);

    // modulo eliminates the overflow visibility
    self.buffer.setValue(index % RANGE, value);
}

pub inline fn getValue(self: *const BitRingBuffer, index: u32) bool {
    std.debug.assert(Index24Utils.getDistance(self.tail, index) >= 0);
    std.debug.assert(Index24Utils.getDistance(self.head, index) < 0);

    // modulo eliminates the overflow visibility
    return self.buffer.isSet(index % RANGE);
}

/// if head is smaller than tail it means it overflowed
pub const RangeBit = struct {
    tail: u32,
    head: u32,
    bit: bool,
};

const BitRingBufferIterator = struct {
    cursor: u32,
    ref: *const BitRingBuffer,
    pub fn next(self: *@This()) ?RangeBit {
        const head = self.ref.getHead();
        if (self.cursor >= head) return null;

        const start = self.cursor;
        var cursor = self.cursor;
        const value = self.ref.getValue(Index24Utils.fix(cursor));
        while (cursor < head and self.ref.getValue(Index24Utils.fix(cursor)) == value)
            cursor += 1;

        if (start == cursor) return null;
        return .{
            .tail = Index24Utils.fix(start),
            .head = Index24Utils.fix(cursor),
            .bit = value,
        };
    }
};

test "Overflow Level 1" {
    var ring: BitRingBuffer = .{ .buffer = .empty, .tail = 412, .head = 412, .capacity = BitRingBuffer.RANGE };
    try std.testing.expectEqual(BitRingBuffer.RANGE, ring.capacity);

    ring.reserve(ring.head);
    try std.testing.expectEqual(BitRingBuffer.RANGE - 1, ring.capacity);

    ring.clear();
    try std.testing.expectEqual(BitRingBuffer.RANGE, ring.capacity);

    ring.reserve(ring.head + BitRingBuffer.RANGE - 1);
    try std.testing.expectEqual(0, ring.capacity);

    ring.setValue(ring.tail, true);
    try std.testing.expectEqual(true, ring.getValue(ring.tail));
}
test "Overflow Level 2" {
    var ring: BitRingBuffer = .{ .buffer = .empty, .tail = 0xFF_FFFE, .head = 0xFF_FFFE, .capacity = BitRingBuffer.RANGE };
    try std.testing.expectEqual(BitRingBuffer.RANGE, ring.capacity);

    ring.reserve(ring.head);
    try std.testing.expectEqual(BitRingBuffer.RANGE - 1, ring.capacity);

    ring.clear();
    try std.testing.expectEqual(BitRingBuffer.RANGE, ring.capacity);
    try std.testing.expectEqual(ring.head, 0xFFFFFF);

    ring.reserve(ring.head + BitRingBuffer.RANGE - 1);
    try std.testing.expectEqual(0, ring.capacity);

    ring.setValue(ring.tail, true);
    try std.testing.expectEqual(true, ring.getValue(ring.tail));
    ring.setValue(ring.tail, false);
    try std.testing.expectEqual(false, ring.getValue(ring.tail));

    try std.testing.expect(ring.head < 0xFFFFFF);

    // Special case of overflow allocation
    ring = .{ .buffer = .empty, .tail = 0xFFFFFF, .head = 0xFFFFFF, .capacity = BitRingBuffer.RANGE };
    try std.testing.expectEqual(BitRingBuffer.RANGE, ring.capacity);

    ring.reserve(0);
    try std.testing.expectEqual(BitRingBuffer.RANGE - 2, ring.capacity);

    var ite = ring.iterator();
    const value = ite.next();

    try std.testing.expect(value != null);

    // false means this range is range of zeros
    try std.testing.expectEqual(false, value.?.bit);

    // bc of overflow, the tail is still big but head small
    try std.testing.expectEqual(2, Index24Utils.getDistance(value.?.tail, value.?.head));
}
