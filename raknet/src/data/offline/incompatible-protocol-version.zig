const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .IncompatibleProtocolVersion;

protocol_version: u8,
magic: raknet.Magic = .{},
server_guid: u64,
