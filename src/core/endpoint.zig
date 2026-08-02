const Io = @import("std").Io;
const Socket = Io.net.Socket;

const IpAddress = @import("../protocol/root.zig").RakAddress.Type;

source: *const Socket,
address: IpAddress,

pub inline fn send(self: *const @This(), io: Io, data: []const u8) Socket.SendError!void {
    try self.source.send(io, &self.address, data);
}
