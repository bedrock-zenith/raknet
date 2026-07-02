const Cursor = @import("../common/cursor.zig");
const std = @import("std");
const Magic = @import("../types/magic.zig").Magic;
const ZeroPedding = @import("../types/zero-pedding.zig");

pub fn serialize(comptime P: type, cursor: *Cursor, packet: P) !void {
    const type_info = @typeInfo(P);

    try cursor.writeByte(@intFromEnum(P.PacketId));

    inline for (type_info.@"struct".fields) |field| {
        switch (field.type) {
            u24 => try cursor.writeInt(field.type, @field(packet, field.name), .little),
            u64, i64, u32, i32 => try cursor.writeInt(field.type, @field(packet, field.name), .big),
            Magic => try cursor.append(&Magic.BYTES),
            []const u8 => try cursor.appendPrexifed(u16, @field(packet, field.name), .big),
            else => @compileError("Unknown type"),
        }
    }
}

pub fn deserialize(comptime P: type, cursor: *Cursor, packet: *P) !void {
    const type_info = @typeInfo(P);
    inline for (type_info.@"struct".fields) |field| {
        switch (field.type) {
            u24 => @field(packet, field.name) = try cursor.readInt(field.type, .little),
            u64, i64, u32, i32 => @field(packet, field.name) = try cursor.readInt(field.type, .big),
            Magic => try cursor.skip(Magic.BYTES.len),
            []const u8 => @field(packet, field.name) = try cursor.readSlicePrefixed(u16, .big),
            else => @compileError("Unknown type"),
        }
    }
}
