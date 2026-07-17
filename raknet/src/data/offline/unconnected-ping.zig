const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .UnconnectedPing;

ping_time: u64,
magic: raknet.Magic = .{},
client_guid: u64,
