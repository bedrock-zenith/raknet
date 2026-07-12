pub const Writer = CursorKind(false);
pub const Reader = CursorKind(true);

fn CursorKind(comptime isReadOnly: bool) type {
    return struct {
        const BufferType = if (isReadOnly) ([]const u8) else []u8;
        const Instance = @This();
        const std = @import("std");

        buffer: BufferType,
        pointer: usize,

        const CursorError = error{
            IndexOutOfBounds,
        };

        pub inline fn init(buffer: BufferType, pointer: usize) Instance {
            return .{ .buffer = buffer, .pointer = pointer };
        }

        pub inline fn reset(cursor: *Instance) void {
            cursor.pointer = 0;
        }

        pub inline fn skip(cursor: *Instance, size: usize) CursorError!void {
            const offset = cursor.pointer +% size;
            if (offset > cursor.buffer.len)
                return error.IndexOutOfBounds;

            cursor.pointer +%= size;
        }
        pub inline fn getProcessedBytes(cursor: *const Instance) BufferType {
            return cursor.buffer[0..cursor.pointer];
        }
        pub inline fn getRemainingBytes(cursor: *const Instance) BufferType {
            return cursor.buffer[cursor.pointer..];
        }

        // ----- Read -----
        pub inline fn readByte(cursor: *Instance) CursorError!u8 {
            const offset = cursor.pointer +% 1;
            if (offset > cursor.buffer.len)
                return error.IndexOutOfBounds;

            const byte = cursor.buffer[cursor.pointer];
            cursor.pointer = offset;
            return byte;
        }

        pub inline fn readInt(cursor: *Instance, comptime T: type, endianness: std.builtin.Endian) CursorError!T {
            const size: comptime_int = @divExact(@typeInfo(T).int.bits, 8);
            const offset = cursor.pointer +% size;
            if (offset > cursor.buffer.len)
                return error.IndexOutOfBounds;

            const ptr: *const [size]u8 = @ptrCast(cursor.buffer[cursor.pointer..offset].ptr);
            const value: T = std.mem.readInt(T, ptr, endianness);

            cursor.pointer = offset;

            return value;
        }

        pub inline fn readSlice(cursor: *Instance, size: usize) CursorError!BufferType {
            const offset = cursor.pointer +% size;
            if (offset > cursor.buffer.len)
                return error.IndexOutOfBounds;

            const slice = cursor.buffer[cursor.pointer..offset];
            cursor.pointer = offset;
            return slice;
        }

        pub inline fn readSlicePrefixed(cursor: *Instance, comptime T: type, endianness: std.builtin.Endian) CursorError!BufferType {
            const length = try readInt(cursor, T, endianness);
            return try readSlice(cursor, length);
        }

        // ----- Write -----
        pub inline fn writeByte(cursor: *Instance, byte: u8) CursorError!void {
            const offset = cursor.pointer +% 1;
            if (offset > cursor.buffer.len)
                return error.IndexOutOfBounds;

            cursor.buffer[cursor.pointer] = byte;
            cursor.pointer = offset;
        }

        pub inline fn writeInt(cursor: *Instance, comptime T: type, value: T, endianness: std.builtin.Endian) CursorError!void {
            const size: comptime_int = @divExact(@typeInfo(T).int.bits, 8);
            const offset = cursor.pointer +% size;
            if (offset > cursor.buffer.len)
                return error.IndexOutOfBounds;

            const ptr: *[size]u8 = @ptrCast(cursor.buffer[cursor.pointer..offset].ptr);
            std.mem.writeInt(T, ptr, value, endianness);
            cursor.pointer = offset;
        }

        pub inline fn appendPrefixed(cursor: *Instance, comptime T: type, buffer: []const u8, endianness: std.builtin.Endian) CursorError!void {
            try writeInt(cursor, T, @intCast(buffer.len), endianness);
            try append(cursor, buffer);
        }

        pub inline fn append(cursor: *Instance, buffer: []const u8) CursorError!void {
            const offset = cursor.pointer +% buffer.len;
            if (offset > cursor.buffer.len)
                return error.IndexOutOfBounds;

            @memcpy(cursor.buffer[cursor.pointer..offset], buffer);
            cursor.pointer = offset;
        }
    };
}
