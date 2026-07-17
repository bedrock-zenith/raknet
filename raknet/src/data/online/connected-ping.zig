const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .ConnectedPing;

ping_time: u64,
