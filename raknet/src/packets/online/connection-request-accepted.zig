const IpAddress = @import("std").Io.net.IpAddress;

pub const PacketId = @import("../packet-id.zig").PacketId.ConnectionRequestAccepted;

const ConnectionRequestAccepted = @This();

client_address: IpAddress,
client_index: u16,
server_net_addresses: [10]IpAddress,
send_ping_time: u64,
send_pong_time: u64,
