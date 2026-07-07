const IpAddress = @import("std").Io.net.IpAddress;

pub const PacketId = @import("../packet-id.zig").PacketId.NewIncomingConnection;

const NewIncomingConnection = @This();

server_address: IpAddress,
client_net_addresses: [10]IpAddress,
send_ping_time: u64,
send_pong_time: u64,
