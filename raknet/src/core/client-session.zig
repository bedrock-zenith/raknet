const std = @import("std");

const Reader = @import("../common/root.zig").Reader;
const Writer = @import("../common/root.zig").Writer;
const binary = @import("../common/root.zig").binary;
const raknet = @import("../protocol/root.zig");
const Connection = @import("connection.zig");
const Endpoint = @import("endpoint.zig");
const Listener = @import("listener.zig");

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
        try handle(self, segment);
    }

    try self.connection.updateAcknowledge();
    try self.connection.tick(@intCast(std.Io.Clock.now(.awake, self.connection.io.*).toMilliseconds()));
}

fn handle(self: *ClientSession, segment: *const raknet.datagram.Segment) !void {
    var reader: Reader = .init(segment.body, 0);
    try reader.assert(1);
    const packet_id: raknet.PacketId = @enumFromInt(reader.readByte());

    switch (packet_id) {
        .ConnectionRequest => try handleConnectionRequest(self, &reader),
        .NewIncomingConnection => try handleNewIncomingConnection(self, &reader),
        .ConnectedPing => try handleConnectedPing(self, &reader),
        .DisconnectionNotification => try handleDisconnectionNotification(self, &reader),
        .GameData => try handleGameData(self, &reader),
        _ => {},
        else => return error.UnexpectedPacked,
    }

    std.log.info("packet_id: {}", .{packet_id});
}

fn handleConnectionRequest(self: *ClientSession, reader: *Reader) !void {
    const packet = try readPacket(reader, raknet.online.ConnectionRequest);

    if (packet.client_guid != self.connection.guid) {
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

fn handleNewIncomingConnection(self: *ClientSession, reader: *Reader) !void {
    _ = reader;
    self.connection.state = .Connected;
}

fn handleConnectedPing(self: *ClientSession, reader: *Reader) !void {
    const packet = try readPacket(reader, raknet.online.ConnectedPing);

    try sendInternal(self, raknet.online.ConnectedPong, &.{
        .ping_time = packet.ping_time,
        .pong_time = @intCast(std.Io.Clock.now(.awake, self.connection.io.*).toMilliseconds()),
    });
}

fn handleDisconnectionNotification(self: *ClientSession, reader: *Reader) !void {
    _ = self; // autofix
    _ = reader; // autofix
    std.log.debug("Client disconnected", .{});
    // todo: clear up connection
}

fn handleGameData(self: *ClientSession, reader: *Reader) !void {
    _ = self; // autofix
    const minecraft_data = reader.getRemainingBytes();
    _ = minecraft_data; // autofix

    // forward data or something like that
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
