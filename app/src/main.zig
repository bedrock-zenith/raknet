const raknet = @import("raknet");
const std = @import("std");
const Io = std.Io;
const net = Io.net;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const guid: u64 = 13253860892328930865;
    const motd = try std.fmt.allocPrint(init.gpa, "MCPE;Dedicated Server;527;1.19.1;0;10;{d};Bedrock level;Survival;1;", .{guid});
    defer init.gpa.free(motd);

    const listenAddress: net.IpAddress = .{
        .ip4 = try .parse("0.0.0.0", 19132),
    };

    const socket = try listenAddress.bind(io, .{ .mode = .dgram });
    var buffer: [2048]u8 = undefined;

    var send_buffer: [2048]u8 = undefined;
    var send_cursor: raknet.Cursor = .init(&send_buffer, 0);

    std.log.info("Server started", .{});

    while (true) {
        var message = socket.receive(io, &buffer) catch |err| switch (err) {
            else => return err,
        };

        var read_cursor: raknet.Cursor = .init(message.data, 1);
        var ping_packet: raknet.UnconnectedPingPacket = undefined;
        try raknet.deserialize(raknet.UnconnectedPingPacket, &read_cursor, &ping_packet);
        std.log.info("ping_time: {d}", .{ping_packet.ping_time});

        try raknet.serialize(raknet.UnconnectedPongPacket, &send_cursor, .{
            .ping_time = ping_packet.ping_time,
            .server_guid = guid,
            .motd = motd,
        });

        try socket.send(io, &message.from, send_buffer[0..send_cursor.cursor]);
        // std.log.debug("DataSize: {s}", .{message.data});

        send_cursor.reset();
    }
}
