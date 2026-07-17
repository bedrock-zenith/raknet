const raknet = @import("../root.zig");

pub const PacketId: raknet.PacketId = .OpenConnectionRequestOne;

magic: raknet.Magic,
protocol_version: u8,
padding: raknet.ZeroPadding,
