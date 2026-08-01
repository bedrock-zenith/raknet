const std = @import("std");
const Allocator = std.mem.Allocator;

const Reader = @import("../common/root.zig").Reader;
const Writer = @import("../common/root.zig").Writer;
const binary = @import("../common/root.zig").binary;
const raknet = @import("../protocol/root.zig");
const logger = @import("../root.zig").raknet_logger;
const Connection = @import("connection.zig");
const destroySegment = @import("connection.zig").destroySegment;
const Endpoint = @import("endpoint.zig");
const Listener = @import("listener.zig");

const STALE_SESSION_TIMEOUT_TICKS = 10_000;

const ClientSession = @This();
connection: Connection,
listener: *Listener,

pub fn init(
    self: *ClientSession,
    listener: *Listener,
    endpoint: *const Endpoint,
    guid: u64,
    mtu: u16,
) Allocator.Error!void {
    self.* = .{
        .listener = listener,
        .connection = undefined,
    };
    try self.connection.init(
        listener.io,
        &listener.pool_allocator,
        listener.allocator,
        endpoint.*,
        listener.last_tick,
        guid,
        mtu,
    );
}

pub fn deinit(self: *ClientSession) void {
    self.connection.deinit();
}

pub fn receive(self: *ClientSession, datagram: []const u8) (Allocator.Error)!void {
    // TODO: handle all possible errors except Allocator.Error
    self.connection.receive(datagram) catch unreachable;

    while (self.connection.rx_received.popFront()) |segment| {
        try rxSingle(self, segment);
    }
}

pub fn tick(self: *ClientSession, current_tick: usize) Allocator.Error!void {
    if (current_tick > self.connection.rx_last_tick + STALE_SESSION_TIMEOUT_TICKS) {
        logger.debug("stale session", .{});
        try disconnect(self);
        return;
    }

    try self.connection.tick(current_tick);
}

pub fn txFlush(self: *ClientSession) std.Io.net.Socket.SendError!void {
    while (self.connection.tx_send.popFront()) |buffer| {
        try self.connection.endpoint.send(self.listener.io, buffer);
        self.connection.pool_allocator.destroy(buffer.ptr);
    }
}

fn rxSingle(self: *ClientSession, segment: *raknet.datagram.Segment) Allocator.Error!void {
    if (segment.body.len == 0) {
        destroySegment(self.connection.pool_allocator, self.connection.gpa, segment);
        return;
    }

    const packet_id: raknet.PacketId = @enumFromInt(segment.body[0]);
    logger.info("packet_id: {}", .{packet_id});

    (switch (packet_id) {
        .ConnectionRequest => rxConnectionRequest(self, segment),
        .NewIncomingConnection => rxNewIncomingConnection(self, segment),
        .ConnectedPing => rxConnectedPing(self, segment),
        .DisconnectionNotification => rxDisconnectionNotification(self, segment),
        .GameData => rxGameData(self, segment),
        _ => destroySegment(self.connection.pool_allocator, self.connection.gpa, segment),
        else => br: {
            destroySegment(self.connection.pool_allocator, self.connection.gpa, segment);
            break :br error.UnexpectedPacket;
        },
    }) catch |err| switch (err) {
        error.InvalidPacket, error.UnexpectedPacket => {},
        else => |e| return e,
    };
}

fn rxConnectionRequest(self: *ClientSession, segment: *raknet.datagram.Segment) (Connection.RxInvalidPacketError || Allocator.Error)!void {
    defer destroySegment(self.connection.pool_allocator, self.connection.gpa, segment);

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
        .send_pong_time = @intCast(std.Io.Clock.now(.awake, self.connection.io).toMilliseconds()),
        .server_net_addresses = @splat(@as(
            raknet.RakAddress.Type,
            .{
                .ip4 = .{ .bytes = @splat(0), .port = 0 },
            },
        )),
    });
}

pub fn disconnect(self: *ClientSession) Allocator.Error!void {
    // todo: send disconnect packet and force it through

    try self.listener.server_events.pushBack(self.listener.allocator, .{
        .disconnected = .{ .session = self },
    });
}

fn rxNewIncomingConnection(self: *ClientSession, segment: *raknet.datagram.Segment) Allocator.Error!void {
    destroySegment(self.connection.pool_allocator, self.connection.gpa, segment);
    self.connection.state = .Connected;
    try self.listener.server_events.pushBack(self.listener.allocator, .{
        .connected = .{
            .session = self,
        },
    });
}

fn rxConnectedPing(self: *ClientSession, segment: *raknet.datagram.Segment) (Connection.RxInvalidPacketError || Allocator.Error)!void {
    defer destroySegment(self.connection.pool_allocator, self.connection.gpa, segment);

    var reader: Reader = .init(segment.body, 1);
    const packet = try readPacket(&reader, raknet.online.ConnectedPing);

    try sendInternal(self, raknet.online.ConnectedPong, &.{
        .ping_time = packet.ping_time,
        .pong_time = @intCast(std.Io.Clock.now(.awake, self.connection.io).toMilliseconds()),
    });
}

fn rxDisconnectionNotification(self: *ClientSession, segment: *raknet.datagram.Segment) Allocator.Error!void {
    defer destroySegment(self.connection.pool_allocator, self.connection.gpa, segment);

    self.connection.state = .Disconnected;
    try self.listener.server_events.pushBack(self.listener.allocator, .{
        .disconnected = .{ .session = self },
    });
}

fn rxGameData(self: *ClientSession, segment: *raknet.datagram.Segment) Allocator.Error!void {
    try self.listener.server_events.pushBack(self.listener.allocator, .{
        .messaged = .{
            .session = self,
            .context = segment,
            .message = segment.body[1..],
        },
    });
}

fn sendInternal(self: *ClientSession, comptime T: type, value: *const T) Allocator.Error!void {
    var writer_buffer: [1024]u8 = undefined;
    var writer: Writer = .init(&writer_buffer, 0);
    writer.writeByte(@intFromEnum(T.PacketId));

    // this method is sendInternal so we can assert that there is no raknet packet bigger than our buffer
    binary.writeAsserted(T, &writer, value) catch unreachable;

    try self.connection.send(writer.getProcessedBytes());
}

inline fn readPacket(reader: *Reader, comptime T: type) Connection.RxInvalidPacketError!T {
    var packet: T = undefined;
    binary.readAsserted(T, reader, &packet) catch return error.InvalidPacket;
    return packet;
}
