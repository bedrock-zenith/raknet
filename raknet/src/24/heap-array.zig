const std = @import("std");
const testing = std.testing;

pub fn HeapArray(comptime T: type, comptime capacity: usize, comptime compareFn: fn (a: T, b: T) bool) type {
    return struct {
        const Self = @This();

        len: usize = 0,
        buffer: [capacity]T = undefined,

        pub inline fn peek(self: *const Self) ?T {
            if (self.len == 0) {
                return null;
            }
            return self.buffer[0];
        }

        pub fn push(self: *Self, item: T) usize {
            std.debug.assert(self.len < capacity);
            const index = self.len;
            self.buffer[index] = item;
            self.len += 1;
            return self.bubbleUp(index);
        }

        pub fn pop(self: *Self) T {
            std.debug.assert(self.len > 0);
            const item = self.buffer[0];
            self.len -= 1;
            if (self.len > 0) {
                self.buffer[0] = self.buffer[self.len];
                _ = self.bubbleDown(0);
            }
            return item;
        }

        fn bubbleUp(self: *Self, start_index: usize) usize {
            var child = start_index;
            while (child > 0) {
                const parent = parentIndex(child);

                if (compareFn(self.buffer[child], self.buffer[parent])) {
                    const temp = self.buffer[parent];
                    self.buffer[parent] = self.buffer[child];
                    self.buffer[child] = temp;
                    child = parent;
                } else break;
            }
            return child;
        }

        fn bubbleDown(self: *Self, start_index: usize) bool {
            var parent = start_index;
            var moved = false;
            while (true) {
                const left = leftIndex(parent);
                if (left >= self.len) break;

                const right = rightIndex(parent);
                var target_child = left;
                if (right < self.len and compareFn(self.buffer[right], self.buffer[left])) {
                    target_child = right;
                }

                if (compareFn(self.buffer[target_child], self.buffer[parent])) {
                    const temp = self.buffer[parent];
                    self.buffer[parent] = self.buffer[target_child];
                    self.buffer[target_child] = temp;
                    parent = target_child;
                    moved = true;
                } else break;
            }
            return moved;
        }

        inline fn parentIndex(index: usize) usize {
            return (index - 1) / 2;
        }

        inline fn leftIndex(index: usize) usize {
            return (index * 2) + 1;
        }

        inline fn rightIndex(index: usize) usize {
            return (index * 2) + 2;
        }
    };
}

fn lessThan(a: u8, b: u8) bool {
    return a < b;
}

test "HeapArray - basic push and pop order" {
    var heap = HeapArray(u8, 10, lessThan){};

    _ = heap.push(50);
    _ = heap.push(10);
    _ = heap.push(30);
    _ = heap.push(5);

    try testing.expectEqual(@as(usize, 4), heap.len);

    try testing.expectEqual(@as(u8, 5), heap.pop());
    try testing.expectEqual(@as(u8, 10), heap.pop());
    try testing.expectEqual(@as(u8, 30), heap.pop());
    try testing.expectEqual(@as(u8, 50), heap.pop());

    try testing.expectEqual(@as(usize, 0), heap.len);
}

fn greaterThan(a: i32, b: i32) bool {
    return a > b;
}

test "HeapArray - max heap comparison" {
    var heap: HeapArray(i32, 10, greaterThan) = .{};

    _ = heap.push(20);
    _ = heap.push(50);
    _ = heap.push(10);

    try testing.expectEqual(@as(i32, 50), heap.pop());
    try testing.expectEqual(@as(i32, 20), heap.pop());
    try testing.expectEqual(@as(i32, 10), heap.pop());
}

test "HeapArray - interleaved push and pop" {
    const fnLess = struct {
        fn comp(a: i32, b: i32) bool {
            return a < b;
        }
    }.comp;

    var heap: HeapArray(i32, 10, fnLess) = .{};

    _ = heap.push(200);
    _ = heap.push(100);

    try testing.expectEqual(@as(i32, 100), heap.pop());

    _ = heap.push(50);
    _ = heap.push(150);

    try testing.expectEqual(@as(i32, 50), heap.pop());
    try testing.expectEqual(@as(i32, 150), heap.pop());
    try testing.expectEqual(@as(i32, 200), heap.pop());
}

test "HeapArray - single element operation" {
    var heap: HeapArray(f32, 5, struct {
        fn comp(a: f32, b: f32) bool {
            return a < b;
        }
    }.comp) = .{};

    _ = heap.push(3.14);
    try testing.expectEqual(@as(usize, 1), heap.len);

    try testing.expectEqual(@as(f32, 3.14), heap.pop());
    try testing.expectEqual(@as(usize, 0), heap.len);
}
