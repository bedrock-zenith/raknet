const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .UnconnectedPong;

ping_time: u64,
server_guid: u64,
magic: raknet.Magic = .{},
motd: []const u8,
