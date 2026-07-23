const std = @import("std");

const Reader = @import("../common/root.zig").Reader;
const Writer = @import("../common/root.zig").Writer;
const binary = @import("../common/root.zig").binary;
const raknet = @import("../protocol/root.zig");
const Connection = @import("connection.zig");
const destroySegment = @import("connection.zig").destroySegment;
const Endpoint = @import("endpoint.zig");
const Listener = @import("listener.zig");

const STALE_SESSION_TIMEOUT_TICKS = 5_000;

const ClientSession = @This();
connection: Connection,
listener: *Listener,

pub fn init(
    self: *ClientSession,
    listener: *Listener,
    endpoint: *const Endpoint,
    guid: u64,
    mtu: u16,
) !void {
    self.* = .{
        .listener = listener,
        .connection = undefined,
    };
    try self.connection.init(
        listener.io,
        &listener.pool_allocator,
        endpoint.*,
        guid,
        mtu,
    );
}

pub fn deinit(self: *ClientSession) void {
    self.connection.deinit();
}

pub fn receive(self: *ClientSession, datagram: []const u8) !void {
    try self.connection.receive(datagram);

    while (self.connection.rx_received.popFront()) |segment| {
        try rxSingle(self, segment);
    }
}

pub fn tick(self: *ClientSession, current_tick: usize) !void {
    if (current_tick > self.connection.rx_last_tick + STALE_SESSION_TIMEOUT_TICKS) {
        try disconnect(self);
        return;
    }

    try self.connection.tick(current_tick);
}

fn rxSingle(self: *ClientSession, segment: *raknet.datagram.Segment) !void {
    if (segment.body.len == 0) {
        destroySegment(self.connection.pool_allocator, segment);
        return;
    }

    const packet_id: raknet.PacketId = @enumFromInt(segment.body[0]);
    std.log.info("packet_id: {}", .{packet_id});

    switch (packet_id) {
        .ConnectionRequest => try rxConnectionRequest(self, segment),
        .NewIncomingConnection => try rxNewIncomingConnection(self, segment),
        .ConnectedPing => try rxConnectedPing(self, segment),
        .DisconnectionNotification => try rxDisconnectionNotification(self, segment),
        .GameData => try rxGameData(self, segment),
        _ => destroySegment(self.connection.pool_allocator, segment),
        else => {
            destroySegment(self.connection.pool_allocator, segment);
            return error.UnexpectedPacked;
        },
    }
}

fn rxConnectionRequest(self: *ClientSession, segment: *raknet.datagram.Segment) !void {
    defer destroySegment(self.connection.pool_allocator, segment);

    var reader: Reader = .init(segment.body, 1);
    const packet = try readPacket(&reader, raknet.online.ConnectionRequest);

    if (packet.client_guid != self.connection.guid) {
        try disconnect(self);
        // todo: disconnect?
    }

    try sendInternal(self, raknet.online.ConnectionRequestAccepted, &.{
        .client_address = self.connection.endpoint.address,
        .client_index = 0,
        .send_ping_time = packet.incoming_timestamp,
        .send_pong_time = @intCast(std.Io.Clock.now(.awake, self.connection.io.*).toMilliseconds()),
        .server_net_addresses = @splat(@as(
            raknet.RakAddress.Type,
            .{
                .ip4 = .{ .bytes = @splat(0), .port = 0 },
            },
        )),
    });
}

pub fn disconnect(self: *ClientSession) !void {
    _ = self; // autofix
    // todo: send disconnect packet and force it through
}

fn rxNewIncomingConnection(self: *ClientSession, segment: *raknet.datagram.Segment) !void {
    destroySegment(self.connection.pool_allocator, segment);
    self.connection.state = .Connected;
    try self.listener.server_events.pushBack(self.listener.allocator, .{
        .connection = .{
            .connection = self,
        },
    });
}

fn rxConnectedPing(self: *ClientSession, segment: *raknet.datagram.Segment) !void {
    defer destroySegment(self.connection.pool_allocator, segment);

    var reader: Reader = .init(segment.body, 1);
    const packet = try readPacket(&reader, raknet.online.ConnectedPing);

    try sendInternal(self, raknet.online.ConnectedPong, &.{
        .ping_time = packet.ping_time,
        .pong_time = @intCast(std.Io.Clock.now(.awake, self.connection.io.*).toMilliseconds()),
    });
}

fn rxDisconnectionNotification(self: *ClientSession, segment: *raknet.datagram.Segment) !void {
    defer destroySegment(self.connection.pool_allocator, segment);

    self.connection.state = .Disconnected;
    _ = self.listener.sessions.remove(self.connection.endpoint.address);
    std.log.debug("Client disconnected", .{});

    try self.listener.server_events.pushBack(self.listener.allocator, .{
        .disconnection = .{ .connection = self },
    });
}

fn rxGameData(self: *ClientSession, segment: *raknet.datagram.Segment) !void {
    try self.listener.server_events.pushBack(self.listener.allocator, .{
        .message = .{
            .connection = self,
            .context = segment,
            .message = segment.body[1..],
        },
    });
}

fn sendInternal(self: *ClientSession, comptime T: type, value: *const T) !void {
    var writer_buffer: [1024]u8 = undefined;
    var writer: Writer = .init(&writer_buffer, 0);
    writer.writeByte(@intFromEnum(T.PacketId));
    try binary.writeAsserted(T, &writer, value);

    try self.connection.send(writer.getProcessedBytes());
}

inline fn readPacket(reader: *Reader, comptime T: type) !T {
    var packet: T = undefined;
    try binary.readAsserted(T, reader, &packet);
    return packet;
}
