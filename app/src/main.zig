const std = @import("std");
const Io = std.Io;
const net = Io.net;

const raknet = @import("raknet");
const Listener = raknet.core.Listener;
const zio = @import("zio");

// ZIO temporary until zig supports receiveTimeout
pub const std_options = std.Options{
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .zio, .level = .err },
    },
};

pub fn main(_: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    const rt = try zio.Runtime.init(gpa, .{});
    defer rt.deinit();
    const io = rt.io();

    const bind_address: net.IpAddress = .{ .ip4 = try .parse("0.0.0.0", 19132) };
    const socket = try bind_address.bind(io, .{ .mode = .dgram });

    var listener: Listener = undefined;
    try listener.init(&io, gpa);

    const motd = try std.fmt.allocPrint(gpa, "MCPE;Dedicated Server;527;1.19.1;0;10;{d};Bedrock level;Survival;1;", .{listener.guid});
    defer gpa.free(motd);

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
        const result = socket.receiveTimeout(io, &receive_buffer, duration);

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

        while (listener.dequeueEvent()) |event| {
            switch (event) {
                .connection => std.log.info("Client connected on ###.###.###.###:{}", .{
                    event.connection.connection.connection.endpoint.address.getPort(),
                }),
                .disconnection => std.log.info("Client connected on ###.###.###.###:{}", .{
                    event.disconnection.connection.connection.endpoint.address.getPort(),
                }),
                .message => |info| {
                    std.log.info("message: {any}", .{info.message});
                    _ = try info.connection.connection.txFlush();
                    try info.connection.connection.send(&.{ 0xfe, 0x0c, 0x8f, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });

                    // 0020   84 03 00 00 60 00 70 01 00 00 01 00 00 00 fe 0c
                    // 0030   8f 01 01 00 00 00 00 00 00 00 00 00
                    //
                    // 0020   80 02 00 00 60 00 70 02 00 00 00 00 00 00 fe 0c
                    // 0030   8f 01 01 00 00 00 00 00 00 00 00 00

                },
            }

            listener.returnEvent(event);
        }

        if (Io.Clock.now(.awake, io).toMilliseconds() >= last_time_tick + TICK_DELTA_TIME) {
            last_time_tick +%= TICK_DELTA_TIME;
            try listener.tick(@intCast(last_time_tick));
        }
    }
}
