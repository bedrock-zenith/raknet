const Magic = @import("../../types/root.zig").Magic;
pub const PacketId = @import("../packet-id.zig").PacketId.AlreadyConnected;

const AlreadyConnected = @This();
magic: Magic = .{},
client_guid: u64,
