pub const PacketId = @import("../packet-id.zig").PacketId.ConnectionRequest;

const ConnectionRequest = @This();

client_guid: u64,
incoming_timestamp: u64,
secure: ?struct {
    client_proof: [32]u8,
    identity_proof: ?[294]u8,
},
