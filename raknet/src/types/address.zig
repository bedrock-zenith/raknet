const IpAddress = @import("std").Io.net.IpAddress;
const Cursor = @import("../common/cursor.zig");

pub fn deserialize(cursor: *Cursor.Reader, address: *IpAddress) !void {
    const version = try cursor.readByte();
    switch (version) {
        4 => {
            const addr: *const [4]u8 = (try cursor.readSlice(4))[0..4];
            const port: u16 = try cursor.readInt(u16, .big);
            address.* = .{
                .ip4 = .{
                    .bytes = addr.*,
                    .port = port,
                },
            };
        },
        6 => {
            // Should be address family, and yes its little endian
            _ = try cursor.readInt(u16, .little);
            const port: u16 = try cursor.readInt(u16, .big);

            const flow: u32 = try cursor.readInt(u32, .big);
            const addr: *const [16]u8 = (try cursor.readSlice(16))[0..16];
            const scopeId: u32 = try cursor.readInt(u32, .big);

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
pub fn serialize(cursor: *Cursor.Writer, address: *const IpAddress) !void {
    switch (address.*) {
        .ip4 => |ip4| {
            try cursor.writeByte(4);
            try cursor.append(&ip4.bytes);
            try cursor.writeInt(u16, ip4.port, .big);
        },
        .ip6 => |ip6| {
            try cursor.writeByte(6);

            // Unknow InnerNetwrokIpv6Interface
            try cursor.writeInt(u16, 0, .little);

            try cursor.writeInt(u16, ip6.port, .big);
            try cursor.writeInt(u32, ip6.flow, .big);
            try cursor.append(&ip6.bytes);
            try cursor.writeInt(u32, ip6.interface.index, .big);
        },
    }
}
