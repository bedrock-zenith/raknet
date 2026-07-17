const std = @import("std");

const raknet = @import("../data/root.zig");
const common = @import("root.zig");

pub inline fn writeAsserted(comptime T: type, cursor: *common.Writer, value: *const T) !void {
    if (sizeof(T)) |size| {
        try cursor.assert(size);
        write(T, cursor, value) catch unreachable;
    } else |_| {
        try write(T, cursor, value);
    }
}
pub inline fn readAsserted(comptime T: type, cursor: *common.Reader, value: *T) !void {
    if (sizeof(T)) |size| {
        try cursor.assert(size);
        read(T, cursor, value) catch unreachable;
    } else |_| {
        try read(T, cursor, value);
    }
}
pub inline fn write(comptime T: type, cursor: *common.Writer, value: *const T) !void {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .int => switch (T) {
            u8, i8 => cursor.writeByte(@bitCast(value.*)),
            u24 => cursor.writeInt(T, value.*, .little),
            else => cursor.writeInt(T, value.*, .big),
        },
        .optional => {
            try cursor.assert(1);
            if (value.*) |*v| {
                cursor.writeByte(1);

                if (sizeof(type_info.optional.child)) |size| {
                    try cursor.assert(size);
                    write(type_info.optional.child, cursor, v) catch unreachable;
                } else |_| {
                    try write(type_info.optional.child, cursor, v);
                }
            } else {
                cursor.writeByte(0);
            }
        },
        .@"struct" => switch (T) {
            raknet.Magic => cursor.append(&raknet.Magic.BYTES),
            raknet.ZeroPadding => cursor.skip(cursor.remaining()),
            else => {
                if (sizeof(T)) |size| {
                    try cursor.assert(size);
                    inline for (type_info.@"struct".fields) |field|
                        write(field.type, cursor, &@field(value, field.name)) catch unreachable;
                } else |_| {
                    inline for (type_info.@"struct".fields) |field| {
                        if (sizeof(field.type)) |size| {
                            try cursor.assert(size);
                            write(field.type, cursor, &@field(value, field.name)) catch unreachable;
                        } else |_| {
                            try write(field.type, cursor, &@field(value, field.name));
                        }
                    }
                }
            },
        },
        .@"union" => switch (T) {
            raknet.RakAddress.Type => try raknet.RakAddress.serialize(cursor, value),
            else => @compileError("Unsupported union type: " ++ @typeName(T)),
        },
        .array => if (sizeof(type_info.array.child)) |size| {
            try cursor.assert(size * type_info.array.len);
            inline for (value) |*element| {
                write(type_info.array.child, cursor, element) catch unreachable;
            }
        } else |_| {
            inline for (value) |*element| {
                try write(type_info.array.child, cursor, element);
            }
        },
        .pointer => switch (type_info.pointer.size) {
            .slice => {
                if (type_info.pointer.child == u8) {
                    try cursor.assert(2 + value.*.len);
                    cursor.appendPrefixed(u16, value.*, .big);
                } else @compileError("Unsupported slice type: " ++ @typeName(T));
            },
            .one => {
                const child_info = @typeInfo(type_info.pointer.child);
                if (child_info == .array) switch (child_info.array.child) {
                    u8 => {
                        try cursor.assert(child_info.array.len);
                        cursor.append(value.*);
                    },
                    else => @compileError("Unsupported array pointer type: " ++ @typeName(T)),
                } else @compileError("Unsupported single pointer type: " ++ @typeName(T));
            },
            else => @compileError("Unsupported pointer type: " ++ @typeName(T)),
        },
        else => @compileError("Unknown or unsupported type: " ++ @typeName(T)),
    }
}

pub inline fn read(comptime T: type, cursor: *common.Reader, value: *T) !void {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .int => switch (T) {
            u8, i8 => value.* = cursor.readByte(),
            u24 => value.* = cursor.readInt(T, .little),
            else => value.* = cursor.readInt(T, .big),
        },
        .optional => {
            try cursor.assert(1);
            const v = cursor.readByte();

            if (v != 0) {
                if (sizeof(type_info.optional.child)) |size| {
                    try cursor.assert(size);
                    read(type_info.optional.child, cursor, &value.*.?) catch unreachable;
                } else |_| {
                    try read(type_info.optional.child, cursor, &value.*.?);
                }
            } else {
                value.* = null;
            }
        },
        .@"struct" => switch (T) {
            raknet.Magic => cursor.skip(raknet.Magic.BYTES.len),
            raknet.ZeroPadding => {
                const size = cursor.remaining();
                cursor.skip(size);
                value.* = .{ .length = size };
            },
            else => {
                if (sizeof(T)) |size| {
                    try cursor.assert(size);
                    inline for (type_info.@"struct".fields) |field|
                        read(field.type, cursor, &@field(value, field.name)) catch unreachable;
                } else |_| {
                    inline for (type_info.@"struct".fields) |field| {
                        if (sizeof(field.type)) |s| {
                            try cursor.assert(s);
                            read(field.type, cursor, &@field(value, field.name)) catch unreachable;
                        } else |_| {
                            try read(field.type, cursor, &@field(value, field.name));
                        }
                    }
                }
            },
        },
        .@"union" => switch (T) {
            raknet.RakAddress.Type => try raknet.RakAddress.deserialize(cursor, value),
            else => @compileError("Unsupported union type: " ++ @typeName(T)),
        },
        .array => if (sizeof(type_info.array.child)) |size| {
            try cursor.assert(size * type_info.array.len);
            inline for (value) |*element| {
                read(type_info.array.child, cursor, element) catch unreachable;
            }
        } else |_| {
            inline for (value) |*element| {
                try read(type_info.array.child, cursor, element);
            }
        },
        .pointer => switch (type_info.pointer.size) {
            .slice => {
                if (type_info.pointer.child == u8) {
                    try cursor.assert(2);
                    const size: u16 = undefined;
                    read(u16, &size);
                    try cursor.assert(size);
                    value.* = cursor.readSlice(size);
                } else @compileError("Unsupported slice type: " ++ @typeName(T));
            },
            .one => {
                const child_info = @typeInfo(type_info.pointer.child);
                if (child_info == .array) switch (child_info.array.child) {
                    u8 => {
                        try cursor.assert(child_info.array.len);
                        value.* = cursor.readSlice(child_info.array.len)[0..child_info.array.len];
                    },
                    else => @compileError("Unsupported array pointer type: " ++ @typeName(T)),
                } else @compileError("Unsupported single pointer type: " ++ @typeName(T));
            },
            else => @compileError("Unsupported pointer type: " ++ @typeName(T)),
        },
        .void => {},
        else => @compileError("Unknown or unsupported type: " ++ @typeName(T)),
    }
}

pub inline fn sizeof(comptime T: type) error{Unsupported}!usize {
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .int => @divExact(@typeInfo(T).int.bits, 8),
        .@"struct" => switch (T) {
            raknet.Magic => raknet.Magic.BYTES.len,
            raknet.ZeroPadding => 0,
            else => {
                comptime var size: usize = 0;
                inline for (type_info.@"struct".fields) |field|
                    size +%= try sizeof(field.type);

                return size;
            },
        },
        .@"union" => error.Unsupported,
        .array => |array_type| array_type.len * try sizeof(array_type.child),
        .pointer => switch (type_info.pointer.size) {
            .one => {
                const child_info = @typeInfo(type_info.pointer.child);
                if (child_info == .array) switch (child_info.array.child) {
                    u8 => return child_info.array.len,
                    else => return error.Unsupported,
                } else return error.Unsupported;
            },
            else => error.Unsupported,
        },
        .void => 0,
        else => error.Unsupported,
    };
}

pub inline fn readU24LE(reader: *common.Reader) u32 {
    var raw: u24 = 0;
    read(u24, reader, &raw) catch unreachable;
    return @intCast(raw);
}
pub inline fn writeU24LE(writer: *common.Writer, value: u32) void {
    write(u24, writer, &@intCast(value)) catch unreachable;
}

pub inline fn writeRange(cursor: *common.Writer, value: raknet.AckRange) !void {
    try cursor.assert(4);
    cursor.writeByte(if (value.min == value.max) 1 else 0);
    writeU24LE(cursor, value.min);

    if (value.min != value.max) {
        try cursor.assert(3);
        writeU24LE(cursor, value.max);
    }
}

pub inline fn readRange(cursor: *common.Reader) !raknet.AckRange {
    var range: raknet.AckRange = undefined;

    try cursor.assert(4);
    const isSingle: bool = cursor.readByte() == 1;
    range.min = readU24LE(cursor);

    if (isSingle) {
        try cursor.assert(3);
        range.max = readU24LE(cursor);
    }

    return range;
}

test "Serializers" {
    var buffer: [4096]u8 = undefined;
    var writer: common.Writer = .init(&buffer, 0);
    var reader: common.Reader = .init(&buffer, 0);

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
