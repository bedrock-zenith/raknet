pub const OpenConnectionRequestOne = @import("./open-connection-request-one.zig");
pub const OpenConnectionReplyOne = @import("./open-connection-reply-one.zig");
pub const OpenConnectionRequestTwo = @import("./open-connection-request-two.zig").OpenConnectionRequestTwo(true);
pub const OpenConnectionReplyTwo = @import("./open-connection-reply-two.zig");

pub const UnconnectedPong = @import("./unconnected-pong.zig");
pub const UnconnectedPing = @import("./unconnected-ping.zig");
pub const IncompatibleProtocolVersion = @import("./incompatible-protocol-version.zig");
