const IpAddress = @import("std").Io.net.IpAddress;
const Cursor = @import("../common/cursor.zig");

pub fn deserialize(cursor: *Cursor) !IpAddress {
    const version = try cursor.readByte();
    switch (version) {
        4 => {
            const address: [4]u8 = try cursor.readSlice(4);
            const port: u16 = try cursor.readInt(u16, .big);
            return .{
                .ip4 = .{
                    .bytes = @as(*const [4]u8, @ptrCast(@alignCast(address.ptr))).*,
                    .port = port,
                },
            };
        },
        6 => {
            // Should be address family, and yes its little endian
            _ = try cursor.readInt(u16, .little);
            const port: u16 = try cursor.readInt(u16, .big);

            const flow: u32 = try cursor.readInt(u32, .big);
            const address: [16]u8 = try cursor.readSlice(16);
            const scopeId: u32 = try cursor.readInt(u32, .big);

            return .{
                .ip6 = .{
                    .bytes = address,
                    .flow = flow,
                    .port = port,
                    .interface = .{ .index = scopeId },
                },
            };
        },
        else => return error.UnsupportedIPVersion,
    }
}
pub fn serialize(cursor: *Cursor, address: *const IpAddress) !void {
    switch (address) {
        .ip4 => {
            try cursor.writeByte(4);
            try cursor.append(address.ip4.bytes);
            try cursor.writeInt(u16, address.ip4.port, .big);
        },
        .ip6 => {
            try cursor.writeByte(6);

            // Unknow InnerNetwrokIpv6Interface
            try cursor.writeInt(u16, 0, .little);

            try cursor.writeInt(u16, address.ip6.port, .big);
            try cursor.writeInt(u32, address.ip6.flow, .big);
            try cursor.append(address.ip6.bytes);
            try cursor.writeInt(u32, address.ip6.interface.index, .big);
        },
        else => return error.UnsupportedIPVersion,
    }
}
