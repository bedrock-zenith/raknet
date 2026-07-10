const std = @import("std");

pub inline fn fix(number: u32) u32 {
    return number & 0xFF_FFFF;
}

test "fix" {
    try std.testing.expectEqual(@as(u32, 1), fix(0xFF_FFFF + 2));
}

/// makes sure the overflowed value is still larger than the overflow cap
pub inline fn cover(number: u32, overflowed: bool) u32 {
    if (overflowed)
        return number +% 0x0100_0000
    else
        return number;
}

pub inline fn hasOverflowed(old: u32, new: u32) bool {
    // old number has to be large enough
    // new number has to be small enough
    // since UDP is unreliable we have window where the index might land

    // This is hacky way to do things, it doesn't even work normally,
    // we just have to be sure the distance between two numbers is small enough
    // Well it's tuned for our UNACKNOWLEDGED_WINDOWS_SIZE
    return ((new < 0xFFF) and (old > 0xF_FFFF));
}

pub inline fn getDistance(old: u32, new: u32) i32 {
    if (hasOverflowed(old, new))
        // u24 0xFFFFFF and 0 has distance of 1
        return @bitCast((new +% 0x0100_0000) -% old)
    else if (hasOverflowed(new, old))
        return @bitCast(new -% (old +% 0x0100_0000))
    else
        return @bitCast(new -% old);
}

test "distance" {
    try std.testing.expectEqual(getDistance(0xFF_FFFF, 1), 2);
    try std.testing.expectEqual(getDistance(0, 0xFF_FFFF), -1);
}
