const std = @import("std");
const Endpoint = @import("../common/endpoint.zig");
const Dispatcher = @import("../common/dispatcher.zig").Dispatcher;
const Reader = @import("../common/cursor.zig").Reader;
const Writer = @import("../common/cursor.zig").Writer;
const PacketId = @import("../packets/packet-id.zig").PacketId;

const Listener = @This();

const IpAddress = std.Io.net.IpAddress;
const MIN_MTU = 576;
const MAX_MTU_FRAME_SIZE = 2048;
const STALE_CONNECTION_TIME_MS = 15_000;
pub const IpAddressIndexContext = struct {
    pub fn eql(_: @This(), a: IpAddress, b: IpAddress) bool {
        return a.eql(&b);
    }
    pub fn hash(_: @This(), key: IpAddress) u64 {
        return std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
    }
};

const ConnectionsDictionary = std.HashMap(IpAddress, ServerConnection, IpAddressIndexContext, 80);
const FramePool = std.heap.MemoryPool([MAX_MTU_FRAME_SIZE]u8);
const ConnectionEvent = Dispatcher(ServerConnection);
const MessageEvent = Dispatcher(struct {
    message: []const u8,
    connection: *const ServerConnection,
});

pub const ServerConnection = struct {};

guid: u64,
io: std.Io,
allocator: std.mem.Allocator,
candidates: ConnectionsDictionary,
connections: ConnectionsDictionary,
frame_pool: FramePool,
onConnected: ConnectionEvent,
onDisconnected: ConnectionEvent,
onMessage: MessageEvent,
motd: []const u8,

pub fn init(io: std.Io, allocator: std.mem.Allocator) !Listener {
    var xiro = std.Random.Xoroshiro128.init(undefined);
    return .{
        .io = io,
        .allocator = allocator,
        .guid = xiro.next(),
        .candidates = .init(allocator),
        .connections = .init(allocator),
        .frame_pool = try .initCapacity(allocator, 64), // 131072
        .onConnected = .empty,
        .onDisconnected = .empty,
        .onMessage = .empty,
        .motd = "",
    };
}

pub fn optimze(self: *Listener) void {
    self.frame_pool.reset(self.allocator, .{ .retain_with_limit = 64 });
}

pub fn deinit(self: *Listener) void {
    self.frame_pool.deinit(self.allocator);
    self.connections.deinit();
    self.candidates.deinit();
}

// common handler for any raw bytes coming in
pub fn receive(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    if (true) try self.offline(buffer, endpoint);
}

// handle all offline packets
fn offline(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    const UnconnectedPingPacket = @import("../packets/unconnected-ping.zig");
    const UnconnectedPongPacket = @import("../packets/unconnected-pong.zig");
    const OpenConnectionRequestOne = @import("../packets/open-connection-request-one.zig");
    const common = @import("../packets/common.zig");

    var reader: Reader = .init(buffer, 0);

    const writer_buffer = try self.frame_pool.create(self.allocator);
    defer self.frame_pool.destroy(writer_buffer);

    var writer: Writer = .init(writer_buffer, 0);
    const packet_id: PacketId = .from(try reader.readByte());

    switch (packet_id) {
        .UnconnectedPing => {
            var packet: UnconnectedPingPacket = undefined;
            try common.deserialize(UnconnectedPingPacket, &reader, &packet);
            try common.serialize(UnconnectedPongPacket, &writer, &.{
                .ping_time = packet.ping_time,
                .server_guid = self.guid,
                .motd = self.motd,
            });
            try endpoint.source.send(self.io, &endpoint.address, writer.getProcessedBytes());
        },
        .OpenConnectionRequestOne => {
            var packet: OpenConnectionRequestOne = undefined;
            try common.deserialize(OpenConnectionRequestOne, &reader, &packet);

            std.log.info("OpenConnectionRequst1 padding_size: {d}", .{packet.padding.length});
        },
        else => {
            std.log.err("Unsupported packet: {s}, size: {d}, packet_id: {d}", .{ @tagName(packet_id), writer.buffer.len, writer.buffer[0] });
        },
    }
}
