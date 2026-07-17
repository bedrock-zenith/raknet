pub const ONLINE_DATAGRAM_BIT_MASK = MESSAGE_BIT_MASK | ACKNOWLEDGE_BIT_MASK | NOT_ACKNOWLEDGE_BIT_MASK;

pub const ACKNOWLEDGE_BIT_MASK = @import("acknowledge.zig").BIT_MASK;
pub const Capsule = @import("message.zig").Capsule;
pub const MESSAGE_BIT_MASK = @import("message.zig").BIT_MASK;
pub const NOT_ACKNOWLEDGE_BIT_MASK = @import("not-acknowledge.zig").BIT_MASK;
