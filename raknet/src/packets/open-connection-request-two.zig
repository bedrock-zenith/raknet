pub const Magic = @import("../types/magic.zig").Magic;
pub const IpAddress = @import("std").Io.net.IpAddress;
pub const Reader = @import("../common/cursor.zig").Reader;

pub fn OpenConnectionRequestTwo(comptime security: bool) type {
    return struct {
        const OpenConnectionRequestTwo = @This();
        pub const PacketId = @import("../packets/packet-id.zig").PacketId.OpenConnectionRequestOne;

        magic: Magic,
        security: if (security) struct {
            cookie: u32,
            challenge: ?*const [64]u8,
        } else void,

        server_address: IpAddress,
        mtu: u16,
        client_guid: u64,
    };
}
