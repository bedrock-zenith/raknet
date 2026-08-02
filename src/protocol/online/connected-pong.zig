const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .ConnectedPong;

ping_time: u64,
pong_time: u64,
