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
    defer listener.deinit();

    const motd = try std.fmt.allocPrint(gpa, "MCPE;Dedicated Server;527;1.19.1;0;10;{d};Bedrock level;Survival;1;", .{listener.guid});
    defer gpa.free(motd);

    listener.motd = motd;

    std.log.info("Server started with port: {d}", .{bind_address.getPort()});

    var receive_buffer: [2048]u8 = undefined;
    const duration: std.Io.Timeout = .{
        .duration = .{
            .clock = .awake,
            .raw = .fromMilliseconds(20),
        },
    };

    var last_time_tick = Io.Clock.now(.awake, io).toMilliseconds();
    const TICK_DELTA_TIME = 20;

    var loop = true;
    while (loop) {
        const result = socket.receiveTimeout(io, &receive_buffer, duration);

        if (result) |message| {
            const endpoint: raknet.core.Endpoint = .{
                .address = message.from,
                .source = &socket,
            };
            listener.receive(message.data, &endpoint, @intCast(last_time_tick));
        } else |err| switch (err) {
            error.Timeout => {},
            else => return err,
        }

        while (listener.dequeueEvent()) |event| {
            defer listener.returnEvent(event);
            switch (event) {
                .connected => |info| std.log.info("Client connected on ###.###.###.###:{}", .{
                    info.session.connection.endpoint.address.getPort(),
                }),
                .disconnected => |info| {
                    std.log.info("Client disconnected on ###.###.###.###:{}", .{
                        info.session.connection.endpoint.address.getPort(),
                    });

                    loop = false;
                },
                .messaged => |message| {
                    std.log.info("message: {any}", .{message.message});

                    // Reply with own network setting packet to the network settings request packet
                    // contains gameheader, size of payload, packet id in varint format and packet data
                    try message.session.connection.send(&.{ 0xfe, 0x0c, 0x8f, 0x01, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });

                    // 0020   84 03 00 00 60 00 70 01 00 00 01 00 00 00 fe 0c
                    // 0030   8f 01 01 00 00 00 00 00 00 00 00 00
                    //
                    // 0020   80 02 00 00 60 00 70 02 00 00 00 00 00 00 fe 0c
                    // 0030   8f 01 01 00 00 00 00 00 00 00 00 00

                },
            }
        }

        const current_time = Io.Clock.now(.awake, io).toMilliseconds();
        if (current_time >= last_time_tick + TICK_DELTA_TIME) {
            last_time_tick +%= TICK_DELTA_TIME;
            try listener.tick(@intCast(last_time_tick));
        }
    }
}
