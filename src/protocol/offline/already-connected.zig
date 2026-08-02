const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .AlreadyConnected;

magic: raknet.Magic = .{},
client_guid: u64,
