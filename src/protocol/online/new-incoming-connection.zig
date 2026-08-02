const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .NewIncomingConnection;

server_address: raknet.RakAddress.Type,
client_net_addresses: [10]raknet.RakAddress.Type,
send_ping_time: u64,
send_pong_time: u64,
