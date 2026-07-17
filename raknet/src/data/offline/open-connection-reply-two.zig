const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .OpenConnectionReplyTwo;

magic: raknet.Magic = .{},
server_guid: u64,
client_address: raknet.RakAddress.Type,
mtu_size: u16,
encryption_key: ?*const [128]u8 = null,
