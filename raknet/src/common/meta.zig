const IpAddress = @import("std").Io.net.IpAddress;
const std = @import("std");

const Cursor = @import("../common/cursor.zig");
const types = @import("../types/root.zig");

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
            types.Magic => try cursor.append(&types.Magic.BYTES),
            types.ZeroPadding => try cursor.skip(cursor.getRemainingBytes().len),
            else => {
                inline for (type_info.@"struct".fields) |field|
                    try write(field.type, cursor, &@field(value, field.name));
            },
        },
        .@"union" => switch (T) {
            IpAddress => try types.RakAddress.serialize(cursor, value),
            else => @compileError("Unsupported union type: " ++ @typeName(T)),
        },
        .array => inline for (value) |*element| {
            try write(type_info.array.child, cursor, element);
        },
        .pointer => switch (type_info.pointer.size) {
            .slice => {
                if (type_info.pointer.child == u8)
                    try cursor.appendPrefixed(u16, value.*, .big)
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
            types.Magic => try cursor.skip(types.Magic.BYTES.len),
            types.ZeroPadding => {
                const size = cursor.getRemainingBytes().len;
                try cursor.skip(size);
                value.* = .{ .length = size };
            },
            else => {
                inline for (type_info.@"struct".fields) |field|
                    try read(field.type, cursor, &@field(value, field.name));
            },
        },
        .@"union" => switch (T) {
            IpAddress => try types.RakAddress.deserialize(cursor, value),
            else => @compileError("Unsupported union type: " ++ @typeName(T)),
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
        .void => {},
        else => @compileError("Unknown or unsupported type: " ++ @typeName(T)),
    }
}

pub inline fn readU24LE(reader: *Cursor.Reader) !u32 {
    var raw: u24 = 0;
    try read(u24, reader, &raw);
    return @intCast(raw);
}
pub inline fn writeU24LE(writer: *Cursor.Writer, value: u32) !void {
    try write(u24, writer, &value);
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
