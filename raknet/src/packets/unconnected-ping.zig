const UnconnectedPongPacket = @This();
const Magic = @import("../types/magic.zig").Magic;

pub const PacketId = @import("./packet-id.zig").PacketId.UnconnectedPing;
ping_time: u64,
magic: Magic = .{},
client_guid: u64,
