const raknet = @import("raknet");
const Listener = raknet.Listener;
const std = @import("std");
const Io = std.Io;
const net = Io.net;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const bind_address: net.IpAddress = .{ .ip4 = try .parse("0.0.0.0", 19132) };
    const socket = try bind_address.bind(io, .{ .mode = .dgram });

    var listener: Listener = try .init(init.io, init.gpa);

    const motd = try std.fmt.allocPrint(init.gpa, "MCPE;Dedicated Server;527;1.19.1;0;10;{d};Bedrock level;Survival;1;", .{listener.guid});
    defer init.gpa.free(motd);

    listener.motd = motd;

    std.log.info("Server started with port: {d}", .{bind_address.getPort()});

    var receive_buffer: [2048]u8 = undefined;
    while (true) {
        const message = socket.receive(io, &receive_buffer) catch |err| switch (err) {
            else => return err,
        };

        const endpoint: raknet.Endpoint = .{
            .address = message.from,
            .source = &socket,
        };
        try listener.receive(message.data, &endpoint);
    }
}
