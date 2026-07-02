const ConnectedPongPacket = @This();

pub const PacketId = @import("../packet-id.zig").PacketId.ConnectedPing;
ping_time: u64,
