const Connection = @import("connection.zig");
pub const Endpoint = @import("endpoint.zig");
const Listener = @import("listener.zig");

const ClientSession = @This();
connection: Connection,
listener: *Listener,

pub fn init(self: *ClientSession, endpoint: *const Endpoint, listener: *Listener, guid: u64) !void {
    self.* = .{
        .listener = listener,
        .connection = undefined,
    };
    try self.connection.init(
        listener.io,
        endpoint.*,
        guid,
        &listener.pool_allocator,
    );
}

pub fn deinit(self: *ClientSession) void {
    self.connection.deinit();
}
