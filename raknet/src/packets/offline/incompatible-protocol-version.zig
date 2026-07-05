const IncompatibleProtocolVersion = @This();
const Magic = @import("../../types/root.zig").Magic;

pub const PacketId = @import("../packet-id.zig").PacketId.IncompatibleProtocolVersion;
protocol_version: u8,
magic: Magic = .{},
server_guid: u64,
