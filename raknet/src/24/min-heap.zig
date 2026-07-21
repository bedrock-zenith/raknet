const std = @import("std");
const testing = std.testing;

const Indexable = @import("utils.zig");

pub fn MinHeap(comptime T: type, comptime size: u32) type {
    return struct {
        const Heap = @This();
        pub const ItemType = struct { order: u32, element: T };
        len: usize = 0,
        buffer: [size]ItemType = undefined,

        pub fn peek(self: *const Heap) ?ItemType {
            if (self.len == 0) {
                return null;
            }

            return self.buffer[0];
        }

        pub fn pop(self: *Heap) T {
            std.debug.assert(self.len > 0);
            const element = self.buffer[0].element;
            self.buffer[0] = self.buffer[self.len -% 1];
            self.len -%= 1;

            var cIndex: usize = 0;
            while (true) {
                const rIndex = rightIndex(cIndex);
                const lIndex = leftIndex(cIndex);

                var nIndex: usize = 0;
                if (lIndex >= self.len) {
                    break;
                } else if (rIndex >= self.len) {
                    nIndex = lIndex;
                } else if (Indexable.distance(self.buffer[lIndex].order, self.buffer[rIndex].order) > 0) {
                    nIndex = lIndex;
                } else {
                    nIndex = rIndex;
                }

                if (Indexable.distance(self.buffer[cIndex].order, self.buffer[nIndex].order) >= 0) {
                    break;
                }

                const temp = self.buffer[cIndex];
                self.buffer[cIndex] = self.buffer[nIndex];
                self.buffer[nIndex] = temp;
                cIndex = nIndex;
            }

            return element;
        }
        /// Returns new index of the element
        pub fn push(self: *Heap, order: u32, element: T) usize {
            std.debug.assert(self.len < size);
            self.buffer[self.len] = .{ .order = order, .element = element };
            var cIndex: usize = self.len;
            self.len +%= 1;
            while (cIndex > 0) {
                const pIndex = parentIndex(cIndex);
                if (Indexable.distance(self.buffer[cIndex].order, self.buffer[pIndex].order) > 0) {
                    const temp = self.buffer[pIndex];
                    self.buffer[pIndex] = self.buffer[cIndex];
                    self.buffer[cIndex] = temp;
                    cIndex = pIndex;
                } else break;
            }
            return cIndex;
        }

        inline fn parentIndex(index: usize) usize {
            return (index -% 1) >> 1;
        }
        inline fn leftIndex(index: usize) usize {
            return (index * 2) +% 1;
        }
        inline fn rightIndex(index: usize) usize {
            return (index * 2) +% 2;
        }
    };
}

test "MinHeap - basic push and pop order" {
    var heap = MinHeap(u8, 10){};

    _ = heap.push(50, 'A');
    _ = heap.push(10, 'B');
    _ = heap.push(30, 'C');
    _ = heap.push(5, 'D');

    try testing.expectEqual(@as(usize, 4), heap.len);

    try testing.expectEqual('D', heap.pop());
    try testing.expectEqual('B', heap.pop());
    try testing.expectEqual('C', heap.pop());
    try testing.expectEqual('A', heap.pop());

    try testing.expectEqual(@as(usize, 0), heap.len);
}

test "MinHeap - duplicate priorities" {
    var heap = MinHeap([]const u8, 5){};

    _ = heap.push(10, "first 10");
    _ = heap.push(10, "second 10");
    _ = heap.push(5, "five");

    try testing.expectEqualStrings("five", heap.pop());

    const elem1 = heap.pop();
    const elem2 = heap.pop();

    const is_valid = std.mem.eql(u8, elem1, "first 10") or std.mem.eql(u8, elem1, "second 10");
    try testing.expect(is_valid);
    try testing.expect(elem1.ptr != elem2.ptr);
}

test "MinHeap - interleaved push and pop" {
    var heap = MinHeap(i32, 10){};

    _ = heap.push(20, 200);
    _ = heap.push(10, 100);

    try testing.expectEqual(@as(i32, 100), heap.pop());

    _ = heap.push(5, 50);
    _ = heap.push(15, 150);

    try testing.expectEqual(@as(i32, 50), heap.pop());
    try testing.expectEqual(@as(i32, 150), heap.pop());
    try testing.expectEqual(@as(i32, 200), heap.pop());
}

test "MinHeap - single element operation" {
    var heap = MinHeap(f32, 5){};

    _ = heap.push(42, 3.14);
    try testing.expectEqual(@as(usize, 1), heap.len);

    try testing.expectEqual(@as(f32, 3.14), heap.pop());
    try testing.expectEqual(@as(usize, 0), heap.len);
}
