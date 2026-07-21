const std = @import("std");
const Index24 = @import("utils.zig");

pub fn BitWindow(comptime range: comptime_int) type {
    comptime {
        if (!std.math.isPowerOfTwo(range))
            @compileError("range must be a power of two.");
        if (range < @bitSizeOf(usize))
            @compileError("range must be at least usize bit size.");
    }

    const USIZE_BITS = @bitSizeOf(usize);
    const USIZE_COUNT = range / USIZE_BITS;

    return struct {
        const Self = @This();
        pub const RANGE: u32 = range;
        pub const RANGE_MASK: u32 = RANGE - 1;

        head: u32 = 0,
        tail: u32 = 0,
        len: u32 = 0,
        words: [USIZE_COUNT]usize = @splat(0),

        pub inline fn clear(self: *Self) void {
            self.tail = self.head;
            self.len = 0;
        }

        /// Fast skip: clear (set to zero) reserved bit range and advance head to newIndex + 1
        pub fn reserve(self: *Self, new: u32) void {
            const new_index = Index24.fixed(new + 1);
            const dist = Index24.distance(self.head, new_index);

            std.debug.assert(dist >= 0);
            const udist: u32 = @bitCast(dist);
            std.debug.assert(self.len + udist <= RANGE);

            if (udist > 0) {
                const head_idx = self.head & RANGE_MASK;
                self.setRangeZeros(head_idx, udist);
                self.len +%= udist;
                self.head = new_index;
            }
        }

        pub inline fn setValue(self: *Self, index: u32, value: bool) void {
            std.debug.assert(Index24.distance(self.tail, index) >= 0);
            std.debug.assert(Index24.distance(self.head, index) < 0);

            const bit_idx = index & RANGE_MASK;
            const word_idx = @divFloor(bit_idx, USIZE_BITS);
            const bit_shift: std.math.Log2Int(usize) = @intCast(bit_idx % USIZE_BITS);
            const mask = @as(usize, 1) << bit_shift;

            if (value) {
                self.words[word_idx] |= mask;
            } else {
                self.words[word_idx] &= ~mask;
            }
        }

        pub inline fn getValue(self: *const Self, index: u32) bool {
            std.debug.assert(Index24.distance(self.tail, index) >= 0);
            std.debug.assert(Index24.distance(self.head, index) < 0);

            const bit_idx = index & RANGE_MASK;
            const word_idx = @divFloor(bit_idx, USIZE_BITS);
            const bit_shift: std.math.Log2Int(usize) = @intCast(bit_idx % USIZE_BITS);

            return ((self.words[word_idx] >> bit_shift) & 1) != 0;
        }

        fn setRangeZeros(self: *Self, start: u32, len: u32) void {
            if (len == 0) return;
            var curr = start;
            var remaining = len;

            while (remaining > 0) {
                const word_idx = @divFloor(curr, USIZE_BITS);
                const bit_in_word = curr % USIZE_BITS;
                const available_in_word = USIZE_BITS - bit_in_word;
                const count = @min(remaining, available_in_word);

                var mask: usize = 0;
                if (count != USIZE_BITS)
                    mask = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(count)) - 1;

                self.words[word_idx] &= ~(mask << @intCast(bit_in_word));

                curr = (curr +% count) & RANGE_MASK;
                remaining -%= count;
            }
        }

        pub const RangeBit = struct {
            tail: u32,
            head: u32,
            bit: bool,
        };

        pub inline fn iterator(self: *const Self) Iterator {
            return .{
                .ref = self,
                .curr_seq = self.tail,
                .remaining = self.len,
            };
        }

        /// Accelerated range iterator using @ctz (count trailing zeros)
        /// Finds contiguous set of bits (either 1s or 0s)
        pub const Iterator = struct {
            ref: *const Self,
            curr_seq: u32,
            remaining: u32,

            pub fn next(self: *Iterator) ?RangeBit {
                if (self.remaining == 0) return null;

                const start_seq = self.curr_seq;
                const target_bit = self.ref.getValue(start_seq);
                var run_len: u32 = 0;

                while (self.remaining > 0) {
                    const bit_idx = self.curr_seq & RANGE_MASK;
                    const word_idx = @divFloor(bit_idx, USIZE_BITS);
                    const bit_in_word = bit_idx % USIZE_BITS;

                    var word = self.ref.words[word_idx];
                    if (target_bit) {
                        word = ~word;
                    }

                    const shifted_word = word >> @intCast(bit_in_word);
                    const avail_in_word = @min(self.remaining, @as(u32, @intCast(USIZE_BITS - bit_in_word)));

                    const trailing = @ctz(shifted_word);
                    const matched_bits = @min(avail_in_word, trailing);

                    if (matched_bits == 0) break;

                    run_len += matched_bits;
                    self.remaining -= matched_bits;
                    self.curr_seq = Index24.fixed(self.curr_seq +% matched_bits);

                    if (matched_bits < avail_in_word) break;
                }

                if (run_len == 0) return null;

                return .{
                    .tail = start_seq,
                    .head = self.curr_seq,
                    .bit = target_bit,
                };
            }
        };
    };
}

test "FastIndexableBitQueue Basic Operations" {
    const Queue = BitWindow(512);
    var q: Queue = .{};

    try std.testing.expectEqual(@as(u32, 0), q.len);

    q.reserve(10);
    try std.testing.expectEqual(@as(u32, 11), q.len);
    try std.testing.expectEqual(@as(u32, 11), q.head);

    q.setValue(5, true);
    try std.testing.expectEqual(true, q.getValue(5));
    try std.testing.expectEqual(false, q.getValue(4));

    q.setValue(5, false);
    try std.testing.expectEqual(false, q.getValue(5));
}

test "FastIndexableBitQueue Range Bit Iteration with Bitwise Accelerators" {
    const Queue = BitWindow(512);
    var q: Queue = .{};

    q.reserve(99);

    var i: u32 = 10;
    while (i <= 19) : (i += 1) q.setValue(i, true);
    i = 50;
    while (i <= 99) : (i += 1) q.setValue(i, true);

    var it = q.iterator();

    const r1 = it.next().?;
    try std.testing.expectEqual(@as(u32, 0), r1.tail);
    try std.testing.expectEqual(@as(u32, 10), r1.head);
    try std.testing.expectEqual(false, r1.bit);

    const r2 = it.next().?;
    try std.testing.expectEqual(@as(u32, 10), r2.tail);
    try std.testing.expectEqual(@as(u32, 20), r2.head);
    try std.testing.expectEqual(true, r2.bit);

    const r3 = it.next().?;
    try std.testing.expectEqual(@as(u32, 20), r3.tail);
    try std.testing.expectEqual(@as(u32, 50), r3.head);
    try std.testing.expectEqual(false, r3.bit);

    const r4 = it.next().?;
    try std.testing.expectEqual(@as(u32, 50), r4.tail);
    try std.testing.expectEqual(@as(u32, 100), r4.head);
    try std.testing.expectEqual(true, r4.bit);

    try std.testing.expectEqual(@as(?Queue.RangeBit, null), it.next());
}

test "FastIndexableBitQueue 24-bit Index Overflow Level 1" {
    const Queue = BitWindow(512);
    var ring: Queue = .{ .tail = 412, .head = 412, .len = 0 };
    try std.testing.expectEqual(@as(u32, 0), ring.len);

    ring.reserve(ring.head);
    try std.testing.expectEqual(@as(u32, 1), ring.len);

    ring.clear();
    try std.testing.expectEqual(@as(u32, 0), ring.len);

    ring.reserve(ring.head + Queue.RANGE - 1);
    try std.testing.expectEqual(Queue.RANGE, ring.len);

    ring.setValue(ring.tail, true);
    try std.testing.expectEqual(true, ring.getValue(ring.tail));
}

test "FastIndexableBitQueue 24-bit Index Overflow Level 2" {
    const Queue = BitWindow(512);
    var ring: Queue = .{ .tail = 0xFF_FFFE, .head = 0xFF_FFFE, .len = 0 };
    try std.testing.expectEqual(@as(u32, 0), ring.len);

    ring.reserve(ring.head);
    try std.testing.expectEqual(@as(u32, 1), ring.len);

    ring.clear();
    try std.testing.expectEqual(@as(u32, 0), ring.len);
    try std.testing.expectEqual(ring.head, 0xFFFFFF);

    ring.reserve(ring.head + Queue.RANGE - 1);
    try std.testing.expectEqual(Queue.RANGE, ring.len);

    ring.setValue(ring.tail, true);
    try std.testing.expectEqual(true, ring.getValue(ring.tail));
    ring.setValue(ring.tail, false);
    try std.testing.expectEqual(false, ring.getValue(ring.tail));

    try std.testing.expect(ring.head < 0xFFFFFF);

    // that crazy wrapping scenario lol
    ring = .{ .tail = 0xFFFFFF, .head = 0xFFFFFF, .len = 0 };
    try std.testing.expectEqual(@as(u32, 0), ring.len);

    ring.reserve(0);
    try std.testing.expectEqual(@as(u32, 2), ring.len);

    var ite = ring.iterator();
    const value = ite.next();

    try std.testing.expect(value != null);
    try std.testing.expectEqual(false, value.?.bit);
    try std.testing.expectEqual(2, Index24.distance(value.?.tail, value.?.head));
}

test "FastIndexableBitQueue Word Boundary Crossing Allocation" {
    const Queue = BitWindow(512);
    var q: Queue = .{};

    q.reserve(59);
    var b: u32 = 0;
    while (b <= 59) : (b += 1) {
        q.setValue(b, true);
    }

    b = 0;
    while (b <= 59) : (b += 1) {
        try std.testing.expectEqual(true, q.getValue(b));
    }

    q.reserve(67);

    b = 60;
    while (b <= 67) : (b += 1) {
        try std.testing.expectEqual(false, q.getValue(b));
    }

    b = 0;
    while (b <= 59) : (b += 1) {
        try std.testing.expectEqual(true, q.getValue(b));
    }
}

test "FastIndexableBitQueue Wrapped Buffer Partial Word Allocation" {
    const Queue = BitWindow(64);
    var q: Queue = .{};

    q.head = 60;
    q.tail = 60;
    q.len = 0;

    q.reserve(60 + 31);
    var i: u32 = 60;
    while (i <= 60 + 31) : (i += 1) q.setValue(i, true);

    q.reserve(60 + 32 + 31);

    i = 60;
    while (i <= 60 + 31) : (i += 1) try std.testing.expectEqual(true, q.getValue(i));

    i = 60 + 32;
    while (i <= 60 + 31 + 32) : (i += 1) try std.testing.expectEqual(false, q.getValue(i));
}
