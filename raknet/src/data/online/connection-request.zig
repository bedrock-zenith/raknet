const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .ConnectionRequest;

client_guid: u64,
incoming_timestamp: u64,
secure: ?struct {
    client_proof: [32]u8,
    identity_proof: ?[294]u8,
},
