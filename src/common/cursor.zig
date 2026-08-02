//  SPDX-License-Identifier: LGPL-3.0-or-later
//  ============================================================================
//   Zenith Raknet - Minecraft Bedrock Raknet
//   Copyright (C) 2026 Bedrock Zenith
//   https://github.com/bedrock-zenith/raknet
//  ============================================================================
//  
//  This file is part of Zenith Raknet.
//  
//  Zenith Raknet is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//  
//  Zenith Raknet is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Lesser General Public License for more details.
//  
//  You should have received a copy of the GNU Lesser General Public License
//  along with Zenith Raknet. If not, see <https://www.gnu.org/licenses/>.

pub const Writer = CursorKind(false);
pub const Reader = CursorKind(true);

pub const CursorError = error{
    IndexOutOfBounds,
};

fn CursorKind(comptime isReadOnly: bool) type {
    return struct {
        pub const Error = CursorError;
        const BufferType = if (isReadOnly) ([]const u8) else []u8;
        const Instance = @This();
        const std = @import("std");

        buffer: BufferType,
        pointer: usize,

        pub inline fn init(buffer: BufferType, pointer: usize) Instance {
            return .{ .buffer = buffer, .pointer = pointer };
        }

        pub inline fn reset(cursor: *Instance) void {
            cursor.pointer = 0;
        }

        pub inline fn skip(cursor: *Instance, size: usize) void {
            const offset = cursor.pointer +% size;
            std.debug.assert(offset <= cursor.buffer.len);

            cursor.pointer +%= size;
        }

        pub inline fn getProcessedBytes(cursor: *const Instance) BufferType {
            return cursor.buffer[0..cursor.pointer];
        }

        pub inline fn getRemainingBytes(cursor: *const Instance) BufferType {
            return cursor.buffer[cursor.pointer..];
        }

        pub inline fn remaining(cursor: *const Instance) usize {
            return cursor.buffer.len - cursor.pointer;
        }

        pub inline fn assert(cursor: *const Instance, bytes: usize) Error!void {
            if (cursor.remaining() < bytes)
                return error.IndexOutOfBounds;
        }

        // ----- Read -----
        pub inline fn readByte(cursor: *Instance) u8 {
            const offset = cursor.pointer +% 1;
            std.debug.assert(offset <= cursor.buffer.len);

            const byte = cursor.buffer[cursor.pointer];
            cursor.pointer = offset;
            return byte;
        }

        pub inline fn readInt(cursor: *Instance, comptime T: type, endianness: std.builtin.Endian) T {
            const size: comptime_int = @divExact(@typeInfo(T).int.bits, 8);
            const offset = cursor.pointer +% size;
            std.debug.assert(offset <= cursor.buffer.len);

            const ptr: *const [size]u8 = @ptrCast(cursor.buffer[cursor.pointer..offset].ptr);
            const value: T = std.mem.readInt(T, ptr, endianness);

            cursor.pointer = offset;

            return value;
        }

        pub inline fn readSlice(cursor: *Instance, size: usize) BufferType {
            const offset = cursor.pointer +% size;
            std.debug.assert(offset <= cursor.buffer.len);

            const slice = cursor.buffer[cursor.pointer..offset];
            cursor.pointer = offset;
            return slice;
        }

        pub inline fn readSlicePrefixed(cursor: *Instance, comptime T: type, endianness: std.builtin.Endian) BufferType {
            const length = readInt(cursor, T, endianness);
            return readSlice(cursor, length);
        }

        // ----- Write -----
        pub inline fn writeByte(cursor: *Instance, byte: u8) void {
            const offset = cursor.pointer +% 1;
            std.debug.assert(offset <= cursor.buffer.len);

            cursor.buffer[cursor.pointer] = byte;
            cursor.pointer = offset;
        }

        pub inline fn writeInt(cursor: *Instance, comptime T: type, value: T, endianness: std.builtin.Endian) void {
            const size: comptime_int = @divExact(@typeInfo(T).int.bits, 8);
            const offset = cursor.pointer +% size;
            std.debug.assert(offset <= cursor.buffer.len);

            const ptr: *[size]u8 = @ptrCast(cursor.buffer[cursor.pointer..offset].ptr);
            std.mem.writeInt(T, ptr, value, endianness);
            cursor.pointer = offset;
        }

        pub inline fn appendPrefixed(cursor: *Instance, comptime T: type, buffer: []const u8, endianness: std.builtin.Endian) void {
            writeInt(cursor, T, @intCast(buffer.len), endianness);
            append(cursor, buffer);
        }

        pub inline fn append(cursor: *Instance, buffer: []const u8) void {
            const offset = cursor.pointer +% buffer.len;
            std.debug.assert(offset <= cursor.buffer.len);

            @memcpy(cursor.buffer[cursor.pointer..offset], buffer);
            cursor.pointer = offset;
        }
    };
}
