const std = @import("std");
const Io = std.Io;
const net = Io.net;

const raknet = @import("raknet");
const Listener = raknet.core.Listener;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const bind_address: net.IpAddress = .{ .ip4 = try .parse("0.0.0.0", 19132) };
    const socket = try bind_address.bind(io, .{ .mode = .dgram });

    var listener: Listener = undefined;
    try listener.init(&init.io, init.gpa);

    const motd = try std.fmt.allocPrint(init.gpa, "MCPE;Dedicated Server;527;1.19.1;0;10;{d};Bedrock level;Survival;1;", .{listener.guid});
    defer init.gpa.free(motd);

    listener.motd = motd;

    std.log.info("Server started with port: {d}", .{bind_address.getPort()});

    var receive_buffer: [2048]u8 = undefined;
    const duration: std.Io.Timeout = .{
        .duration = .{
            .clock = .awake,
            .raw = .fromMilliseconds(10),
        },
    };

    var last_time_tick = Io.Clock.now(.awake, io).toMilliseconds();
    const TICK_DELTA_TIME = 10;
    while (true) {
        const result = socket.receiveTimeout(
            io,
            &receive_buffer,
            duration,
        );

        if (result) |message| {
            const endpoint: raknet.core.Endpoint = .{
                .address = message.from,
                .source = &socket,
            };
            listener.receive(message.data, &endpoint);
        } else |err| switch (err) {
            error.Timeout => {},
            else => return err,
        }

        if (Io.Clock.now(.awake, io).toMilliseconds() >= last_time_tick + TICK_DELTA_TIME) {
            last_time_tick +%= TICK_DELTA_TIME;
            try listener.tick(@intCast(last_time_tick));
        }
    }
}
