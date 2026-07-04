const OpenConnectionRequestOne = @This();
const Magic = @import("../../types/root.zig").Magic;

pub const PacketId = @import("../packet-id.zig").PacketId.OpenConnectionReplyOne;
magic: Magic = .{},
server_guid: u64,
security: ?u32,
mtu_size: u16
