const OpenConnectionRequestOne = @This();
pub const Magic = @import("../types/magic.zig").Magic;

pub const PacketId = @import("../packets/packet-id.zig").PacketId.OpenConnectionReplyOne;
magic: Magic,
server_guid: u64,
security: ?u32,
mtu_size: u16
