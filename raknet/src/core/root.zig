pub const Endpoint = @import("endpoint.zig");
pub const Server = @import("server.zig");
pub const ClientConnection = Server.ClientConnection;

pub const FramePool = @import("../common/root.zig").PoolAllocator(2048);
