const Cursor = @This();
const std = @import("std");

buffer: []u8,
cursor: usize,

const CursorError = error{
    IndexOutOfBounds,
};

pub inline fn init(buffer: []u8, cursor: usize) Cursor {
    return .{ .buffer = buffer, .cursor = cursor };
}

pub inline fn reset(cursor: *Cursor) void {
    cursor.cursor = 0;
}

pub inline fn skip(cursor: *Cursor, size: usize) CursorError!void {
    const offset = cursor.cursor +% size;
    if (offset > cursor.buffer.len)
        return error.IndexOutOfBounds;

    cursor.cursor +%= size;
}

// ----- Read -----
pub inline fn readByte(cursor: *Cursor) CursorError!u8 {
    const offset = cursor.cursor +% 1;
    if (offset > cursor.buffer.len)
        return error.IndexOutOfBounds;

    const byte = cursor.buffer[cursor.cursor];
    cursor.cursor = offset;
    return byte;
}

pub inline fn readInt(cursor: *Cursor, comptime T: type, endianness: std.builtin.Endian) CursorError!T {
    const size: comptime_int = @divExact(@typeInfo(T).int.bits, 8);
    const offset = cursor.cursor +% size;
    if (offset > cursor.buffer.len)
        return error.IndexOutOfBounds;

    const ptr: *[size]u8 = @ptrCast(cursor.buffer[cursor.cursor..offset].ptr);
    const value: T = std.mem.readInt(T, ptr, endianness);

    cursor.cursor = offset;

    return value;
}

pub inline fn readSlice(cursor: *Cursor, size: usize) CursorError![]u8 {
    const offset = cursor.cursor +% size;
    if (offset > cursor.buffer.len)
        return error.IndexOutOfBounds;

    const slice = cursor.buffer[cursor.cursor..offset];
    cursor.cursor = offset;
    return slice;
}

pub inline fn readSlicePrefixed(cursor: *Cursor, comptime T: type, endianness: std.builtin.Endian) CursorError![]u8 {
    const length = try readInt(cursor, T, endianness);
    return try readSlice(cursor, length);
}

// ----- Write -----
pub fn writeByte(cursor: *Cursor, byte: u8) CursorError!void {
    const offset = cursor.cursor +% 1;
    if (offset > cursor.buffer.len)
        return error.IndexOutOfBounds;

    cursor.buffer[cursor.cursor] = byte;
    cursor.cursor = offset;
}

pub inline fn writeInt(cursor: *Cursor, comptime T: type, value: T, endianness: std.builtin.Endian) CursorError!void {
    const size: comptime_int = @divExact(@typeInfo(T).int.bits, 8);
    const offset = cursor.cursor +% size;
    if (offset > cursor.buffer.len)
        return error.IndexOutOfBounds;

    const ptr: *[size]u8 = @ptrCast(cursor.buffer[cursor.cursor..offset].ptr);
    std.mem.writeInt(T, ptr, value, endianness);
    cursor.cursor = offset;
}

pub inline fn appendPrexifed(cursor: *Cursor, comptime T: type, buffer: []const u8, endianness: std.builtin.Endian) CursorError!void {
    try writeInt(cursor, T, @intCast(buffer.len), endianness);
    try append(cursor, buffer);
}

pub inline fn append(cursor: *Cursor, buffer: []const u8) CursorError!void {
    const offset = cursor.cursor +% buffer.len;
    if (offset > cursor.buffer.len)
        return error.IndexOutOfBounds;

    @memcpy(cursor.buffer[cursor.cursor..offset], buffer);
    cursor.cursor = offset;
}

test "test" {
    var buffer: [1024]u8 = undefined;
    var write_cursor: Cursor = .init(&buffer, 0);
    var read_cursor: Cursor = .init(&buffer, 0);

    const testin_value: u16 = 564;
    try write_cursor.writeInt(u16, testin_value, .big);
    try std.testing.expectEqual(testin_value, try read_cursor.readInt(u16, .big));
}
