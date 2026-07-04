const OpenConnectionRequestOne = @This();
const Magic = @import("../../types/root.zig").Magic;
const ZeroPadding = @import("../../types/root.zig").ZeroPadding;

pub const PacketId = @import("../packet-id.zig").PacketId.OpenConnectionRequestOne;
magic: Magic,
protocol_version: u8,
padding: ZeroPadding,
