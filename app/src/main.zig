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

pub fn main(init: std.process.Init) !void {
    const gpa = std.heap.smp_allocator;
    // const rt = try zio.Runtime.init(gpa, .{});
    // defer rt.deinit();
    // const io = rt.io();

    const io = init.io;

    const bind_address: net.IpAddress = .{ .ip4 = try .parse("0.0.0.0", 19132) };
    const socket = try bind_address.bind(io, .{ .mode = .dgram });
    defer socket.close(io);

    var listener: Listener = undefined;
    try listener.init(&io, gpa);
    defer listener.deinit();

    const motd = try std.fmt.allocPrint(gpa, "MCPE;Dedicated Server;527;1.19.1;0;10;{d};Bedrock level;Survival;1;", .{listener.guid});
    defer gpa.free(motd);

    listener.motd = motd;

    std.log.info("Server started with port: {d}", .{bind_address.getPort()});

    const TICK_DELTA_TIME = 10;
    var receive_buffer: [2048]u8 = undefined;
    const duration: std.Io.Timeout = .{
        .duration = .{
            .clock = .awake,
            .raw = .fromMilliseconds(TICK_DELTA_TIME),
        },
    };
    _ = duration; // autofix

    var last_time_tick = Io.Clock.now(.awake, io).toMilliseconds();

    // temporary solution for testing
    var network_settings_send = false;

    var loop = true;
    while (loop) {
        const result = try socket.receive(io, &receive_buffer);
        const endpoint: raknet.core.Endpoint = .{
            .address = result.from,
            .source = &socket,
        };

        listener.receive(result.data, &endpoint, @intCast(last_time_tick));

        // const result = socket.receiveTimeout(io, &receive_buffer, duration);

        // if (result) |message| {
        //     const endpoint: raknet.core.Endpoint = .{
        //         .address = message.from,
        //         .source = &socket,
        //     };
        //     listener.receive(message.data, &endpoint, @intCast(last_time_tick));
        // } else |err| switch (err) {
        //     error.Timeout => {},
        //     else => return err,
        // }
        //

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
                    // std.log.info("message: {any}", .{message.message});

                    var reader: raknet.common.Reader = .init(message.message, 0);

                    if (network_settings_send) {
                        const compression = reader.readByte();
                        _ = compression; // autofix
                    }
                    while (reader.remaining() > 0) {
                        const size = try readLEB128(&reader, u32);
                        std.log.info("size: {}, received_buffer_size: {}", .{ size, message.message.len });
                        try reader.assert(size);

                        const next_checkpoint = reader.pointer + @as(usize, @intCast(size));

                        const packet_id = try readLEB128(&reader, u32);
                        std.log.info("game_packet_id: {}", .{packet_id});

                        switch (packet_id) {
                            193 => {
                                // Reply with own network setting packet to the network settings request packet
                                // contains gameheader, size of payload, packet id in varint format and packet data
                                try message.session.connection.send(&.{ 0xfe, 0x0c, 0x8f, 0x01, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
                                network_settings_send = true;
                            },
                            else => {},
                        }

                        reader.pointer = next_checkpoint;
                    }

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
            last_time_tick = current_time;
            try listener.tick(@intCast(last_time_tick));
        }
    }
}

pub inline fn readLEB128(self: *raknet.common.Reader, comptime T: type) !T {
    comptime if (@typeInfo(T).int.signedness == .signed) @compileError("Allowed only unsigned int");
    var result: T = 0;
    var shift: usize = 0; // must be relative to
    while (self.pointer < self.buffer.len) {
        @branchHint(.likely);
        const byte = self.buffer[self.pointer];
        self.pointer +%= 1;

        result |= (@as(T, byte & 0x7F) << @intCast(shift));

        if ((byte & 0x80) == 0)
            return result;

        shift += 7;
        if (shift >= @typeInfo(T).int.bits)
            return error.LEB128Overflow;
    }

    return error.OutOfBounds;
}
