const std = @import("std");

const MAX_U24: u32 = @intCast(std.math.maxInt(u24));
const HALF_U24: u32 = @divTrunc(MAX_U24, 2);

pub inline fn fixed(number: u32) u32 {
    return number & MAX_U24;
}

test "fixed" {
    try std.testing.expectEqual(@as(u32, 1), fixed(0xFF_FFFF + 2));
}

pub inline fn overflowed(old: u32, new: u32) bool {
    return ((new -% old) & MAX_U24) >= HALF_U24;
}

pub inline fn distance(old: u32, new: u32) i32 {
    const diff = (new -% old) & MAX_U24;

    if (diff >= HALF_U24) {
        return @bitCast(diff -% 0x0100_0000);
    }

    return @bitCast(diff);
}

test "distance" {
    try std.testing.expectEqual(distance(0xFF_FFFF, 1), 2);
    try std.testing.expectEqual(distance(0, 0xFF_FFFF), -1);
}
