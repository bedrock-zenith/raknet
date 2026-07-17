const Socket = @import("std").Io.net.Socket;

const IpAddress = @import("../data/root.zig").RakAddress.Type;

source: *const Socket,
address: IpAddress,
