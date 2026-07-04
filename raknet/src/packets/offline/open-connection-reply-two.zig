const OpenConnectionReplyTwo = @This();
const Magic = @import("../../types/root.zig").Magic;
const IpAddress = @import("std").Io.net.IpAddress;

pub const PacketId = @import("../packet-id.zig").PacketId.OpenConnectionReplyTwo;
magic: Magic = .{},
server_guid: u64,
client_address: IpAddress,
mtu_size: u16,
encryption_key: ?*const [128]u8 = null,
