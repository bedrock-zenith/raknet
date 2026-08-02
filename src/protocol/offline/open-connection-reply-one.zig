const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .OpenConnectionReplyOne;

magic: raknet.Magic = .{},
server_guid: u64,
security: ?u32,
mtu_size: u16
