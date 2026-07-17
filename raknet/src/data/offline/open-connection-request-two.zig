const raknet = @import("../root.zig");

pub fn OpenConnectionRequestTwo(comptime security: bool) type {
    return struct {
        pub const PacketId: raknet.PacketId = .OpenConnectionRequestTwo;

        magic: raknet.Magic,
        security: if (security) struct {
            cookie: u32,
            challenge: ?*const [64]u8,
        } else void,

        server_address: raknet.RakAddress.Type,
        mtu: u16,
        client_guid: u64,
    };
}
