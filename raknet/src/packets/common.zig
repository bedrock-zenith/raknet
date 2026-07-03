const Cursor = @import("../common/cursor.zig");
const std = @import("std");
const Magic = @import("../types/magic.zig").Magic;
const ZeroPadding = @import("../types/zero-padding.zig");

pub fn serialize(comptime P: type, cursor: *Cursor.Writer, packet: *const P) !void {
    const type_info = @typeInfo(P);

    try cursor.writeByte(@intFromEnum(P.PacketId));

    inline for (type_info.@"struct".fields) |field| {
        switch (field.type) {
            u8 => try cursor.writeByte(@field(packet, field.name)),
            u24 => try cursor.writeInt(field.type, @field(packet, field.name), .little),
            u64, i64, u32, i32 => try cursor.writeInt(field.type, @field(packet, field.name), .big),
            ?u32 => {
                if (@field(packet, field.name)) |value| {
                    try cursor.writeByte(1);
                    try cursor.writeInt(@typeInfo(field.type).optional.child, value, .big);
                } else try cursor.writeByte(0);
            },
            Magic => try cursor.append(&Magic.BYTES),
            []const u8 => try cursor.appendPrexifed(u16, @field(packet, field.name), .big),
            ZeroPadding => try cursor.skip(cursor.getRemainingBytes().len),
            else => @compileError("Unknown type: " ++ @typeName(field.type) ++ " of field: " ++ field.name),
        }
    }
}

pub fn deserialize(comptime P: type, cursor: *Cursor.Reader, packet: *P) !void {
    const type_info = @typeInfo(P);
    inline for (type_info.@"struct".fields) |field| {
        switch (field.type) {
            u8 => @field(packet, field.name) = try cursor.readByte(),
            u24 => @field(packet, field.name) = try cursor.readInt(field.type, .little),
            u64, i64, u32, i32 => @field(packet, field.name) = try cursor.readInt(field.type, .big),
            ?u32 => {
                if (try cursor.readByte()) {
                    @field(packet, field.name) = try cursor.readInt(@typeInfo(field.type).optional.child, .big);
                } else @field(packet, field.name) = null;
            },
            Magic => try cursor.skip(Magic.BYTES.len),
            []const u8 => @field(packet, field.name) = try cursor.readSlicePrefixed(u16, .big),
            ZeroPadding => @field(packet, field.name) = .{ .length = cursor.getRemainingBytes().len },
            else => @compileError("Unknown type: " ++ @typeName(field.type) ++ " of field: " ++ field.name),
        }
    }
}
