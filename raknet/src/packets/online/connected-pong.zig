const ConnectedPongPacket = @This();

pub const PacketId = @import("../packet-id.zig").PacketId.ConnectedPong;
ping_time: u64,
pong_time: u64,
