const UnconnectedPongPacket = @This();
const Magic = @import("../types/magic.zig").Magic;

pub const PacketId = @import("./packet-id.zig").PacketId.UnconnectedPong;
ping_time: u64,
server_guid: u64,
magic: Magic = .{},
motd: []const u8,
