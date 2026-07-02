pub const Cursor = @import("./common/cursor.zig");
pub const PacketId = @import("./packets/packet-id.zig").PacketId;
pub const common = @import("./packets/common.zig");
pub const serialize = common.serialize;
pub const deserialize = common.deserialize;
pub const Magic = common.Magic;

pub const UnconnectedPongPacket = @import("./packets/unconnected-pong.zig");
pub const UnconnectedPingPacket = @import("./packets/unconnected-ping.zig");
pub const OpenConnectionRequestOne = @import("./packets/open-connection-request-one.zig");
pub const RakAddress = @import("./types/address.zig");

// -------- Constants --------
test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
