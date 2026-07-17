pub const Type = @import("std").Io.net.IpAddress;

const Cursor = @import("../common/cursor.zig");

pub fn deserialize(cursor: *Cursor.Reader, address: *Type) !void {
    try cursor.assert(1);
    const version = cursor.readByte();
    switch (version) {
        4 => {
            try cursor.assert(6);

            const addr: *const [4]u8 = cursor.readSlice(4)[0..4];
            const port: u16 = cursor.readInt(u16, .big);
            address.* = .{
                .ip4 = .{
                    .bytes = addr.*,
                    .port = port,
                },
            };
        },
        6 => {
            try cursor.assert(28);
            // Should be address family, and yes its little endian
            _ = cursor.readInt(u16, .little);
            const port: u16 = cursor.readInt(u16, .big);

            const flow: u32 = cursor.readInt(u32, .big);
            const addr: *const [16]u8 = cursor.readSlice(16)[0..16];
            const scopeId: u32 = cursor.readInt(u32, .big);

            address.* = .{ .ip6 = undefined };
            address.*.ip6 = .{
                .bytes = addr.*,
                .flow = flow,
                .port = port,
                .interface = .{ .index = scopeId },
            };
        },
        else => return error.UnsupportedIPVersion,
    }
}
pub fn serialize(cursor: *Cursor.Writer, address: *const Type) !void {
    switch (address.*) {
        .ip4 => |ip4| {
            try cursor.assert(7);

            cursor.writeByte(4);
            cursor.append(&ip4.bytes);
            cursor.writeInt(u16, ip4.port, .big);
        },
        .ip6 => |ip6| {
            try cursor.assert(29);

            cursor.writeByte(6);

            // Unknow InnerNetwrokIpv6Interface
            cursor.writeInt(u16, 0, .little);

            cursor.writeInt(u16, ip6.port, .big);
            cursor.writeInt(u32, ip6.flow, .big);
            cursor.append(&ip6.bytes);
            cursor.writeInt(u32, ip6.interface.index, .big);
        },
    }
}
