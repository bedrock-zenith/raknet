const Magic = @import("../../types/root.zig").Magic;
const IpAddress = @import("std").Io.net.IpAddress;

pub fn OpenConnectionRequestTwo(comptime security: bool) type {
    return struct {
        pub const PacketId = @import("../packet-id.zig").PacketId.OpenConnectionRequestOne;

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
