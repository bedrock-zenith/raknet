const OpenConnectionRequestOne = @This();
pub const Magic = @import("../types/magic.zig").Magic;
pub const ZeroPadding = @import("../types/zero-padding.zig");

pub const PacketId = @import("../packets/packet-id.zig").PacketId.OpenConnectionRequestOne;
magic: Magic,
protocol_version: u8,
padding: ZeroPadding,
