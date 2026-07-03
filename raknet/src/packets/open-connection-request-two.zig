const OpenConnectionRequestTwo = @This();
pub const Magic = @import("../types/magic.zig").Magic;
pub const IpAddress = @import("std").Io.net.IpAddress;
pub const Reader = @import("../common/cursor.zig").Reader;

pub const PacketId = @import("../packets/packet-id.zig").PacketId.OpenConnectionRequestOne;
magic: Magic,
server_address: IpAddress,
security: ?struct {
    cookie: u32,
    challange: ?*const [64]u8,
},
mtu_size: u16,
client_guid: u64,

pub fn deserialize(_: *Reader) void {}
