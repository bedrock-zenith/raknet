pub const ONLINE_DATAGRAM_BIT_MASK = DATAGRAM_BIT_MASK | ACKNOWLEDGE_BIT_MASK | NOT_ACKNOWLEDGE_BIT_MASK;

pub const ACKNOWLEDGE_BIT_MASK = @import("acknowledge.zig").BIT_MASK;
pub const ACKNOWLEDGE_PACKED_ID = @import("acknowledge.zig").PACKED_ID;
pub const DATAGRAM_BIT_MASK = @import("datagram.zig").BIT_MASK;
pub const NOT_ACKNOWLEDGE_BIT_MASK = @import("not-acknowledge.zig").BIT_MASK;
pub const NOT_ACKNOWLEDGE_PACKED_ID = @import("not-acknowledge.zig").PACKED_ID;
pub const Segment = @import("datagram.zig").Segment;
