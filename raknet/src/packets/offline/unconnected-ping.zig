const UnconnectedPongPacket = @This();
const Magic = @import("../../types/root.zig").Magic;

pub const PacketId = @import("../packet-id.zig").PacketId.UnconnectedPing;
ping_time: u64,
magic: Magic = .{},
client_guid: u64,
