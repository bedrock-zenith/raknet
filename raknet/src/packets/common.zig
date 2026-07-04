const Cursor = @import("../common/cursor.zig");
const std = @import("std");
const Magic = @import("../types/magic.zig").Magic;
const ZeroPadding = @import("../types/zero-padding.zig");

const opt: *?u32 = null;

pub inline fn write(comptime T: type, cursor: *Cursor.Writer, value: *const T) !void {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .int => switch (T) {
            u8, i8 => try cursor.writeByte(@bitCast(value.*)),
            u24 => try cursor.writeInt(T, value.*, .little),
            else => try cursor.writeInt(T, value.*, .big),
        },
        .optional => if (value.*) |*v| {
            try cursor.writeByte(1);
            try write(type_info.optional.child, cursor, v);
        } else {
            try cursor.writeByte(0);
        },
        .@"struct" => switch (T) {
            Magic => try cursor.append(&Magic.BYTES),
            ZeroPadding => try cursor.skip(cursor.getRemainingBytes().len),
            else => {
                inline for (type_info.@"struct".fields) |field|
                    try write(field.type, cursor, &@field(value, field.name));
            },
        },
        .array => inline for (value) |*element| {
            try write(type_info.array.child, cursor, element);
        },
        .pointer => switch (type_info.pointer.size) {
            .slice => {
                if (type_info.pointer.child == u8)
                    try cursor.appendPrexifed(u16, value.*, .big)
                else
                    @compileError("Unsupported slice type: " ++ @typeName(T));
            },
            .one => {
                const child_info = @typeInfo(type_info.pointer.child);
                if (child_info == .array) switch (child_info.array.child) {
                    u8 => try cursor.append(value.*),
                    else => @compileError("Unsupported array pointer type: " ++ @typeName(T)),
                } else @compileError("Unsupported single pointer type: " ++ @typeName(T));
            },
            else => @compileError("Unsupported pointer type: " ++ @typeName(T)),
        },
        else => @compileError("Unknown or unsupported type: " ++ @typeName(T)),
    }
}

pub inline fn read(comptime T: type, cursor: *Cursor.Reader, value: *T) !void {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .int => switch (T) {
            u8, i8 => value.* = try cursor.readByte(),
            u24 => value.* = try cursor.readInt(T, .little),
            else => value.* = try cursor.readInt(T, .big),
        },
        .optional => if (try cursor.readByte() != 0) {
            try read(type_info.optional.child, cursor, &value.*.?);
        } else {
            value.* = null;
        },
        .@"struct" => switch (T) {
            Magic => try cursor.skip(Magic.BYTES.len),
            ZeroPadding => {
                const size = cursor.getRemainingBytes().len;
                try cursor.skip(size);
                value.* = .{ .length = size };
            },
            else => {
                inline for (type_info.@"struct".fields) |field|
                    try read(field.type, cursor, &@field(value, field.name));
            },
        },
        .array => for (value) |*element| {
            try read(type_info.array.child, cursor, element);
        },
        .pointer => switch (type_info.pointer.size) {
            .slice => {
                if (type_info.pointer.child == u8)
                    value.* = try cursor.readSlicePrefixed(u16, .big)
                else
                    @compileError("Unsupported slice type: " ++ @typeName(T));
            },
            .one => {
                const child_info = @typeInfo(type_info.pointer.child);
                if (child_info == .array) switch (child_info.array.child) {
                    u8 => value.* = (try cursor.readSlice(child_info.array.len))[0..child_info.array.len],
                    else => @compileError("Unsupported array pointer type: " ++ @typeName(T)),
                } else @compileError("Unsupported single pointer type: " ++ @typeName(T));
            },
            else => @compileError("Unsupported pointer type: " ++ @typeName(T)),
        },
        else => @compileError("Unknown or unsupported type: " ++ @typeName(T)),
    }
}

test "Serializers" {
    var buffer: [4096]u8 = undefined;
    var writer: Cursor.Writer = .init(&buffer, 0);
    var reader: Cursor.Reader = .init(&buffer, 0);

    const TestStruct = struct {
        optional: ?u64,
        segment: [4]u64,
        segments: *const [16]u8,
    };

    try write(TestStruct, &writer, &.{
        .optional = null,
        .segment = .{ 654, 654, 654, 654 },
        .segments = "0123456789abcdef",
    });

    var teststr: TestStruct = .{ .optional = 65, .segment = undefined, .segments = undefined };
    try read(TestStruct, &reader, &teststr);

    try std.testing.expectEqual(teststr.optional, null);
    try std.testing.expectEqual(teststr.segment, .{ 654, 654, 654, 654 });
    try std.testing.expectEqualStrings(teststr.segments, "0123456789abcdef");
}
