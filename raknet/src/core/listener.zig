const std = @import("std");
const Endpoint = @import("../common/endpoint.zig");
const Dispatcher = @import("../common/dispatcher.zig").Dispatcher;
const Reader = @import("../common/cursor.zig").Reader;
const Writer = @import("../common/cursor.zig").Writer;
const PacketId = @import("../packets/packet-id.zig").PacketId;
const MAX_MTU_SIZE = @import("./well-known.zig").MAX_MTU_SIZE;
const UDP_HEADER_SIZE = @import("./well-known.zig").UDP_HEADER_SIZE;

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

pub fn receive(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    if (true) try self.offline(buffer, endpoint);
}

fn offline(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    const UnconnectedPingPacket = @import("../packets/unconnected-ping.zig");
    const UnconnectedPongPacket = @import("../packets/unconnected-pong.zig");
    const OpenConnectionRequestOne = @import("../packets/open-connection-request-one.zig");
    const OpenConnectionReplyOne = @import("../packets/open-connection-reply-one.zig");
    //const OpenConnectionRequestTwoSecurity = @import("../packets/open-connection-request-two.zig").OpenConnectionRequestTwo(true);
    const OpenConnectionRequestTwoSafeless = @import("../packets/open-connection-request-two.zig").OpenConnectionRequestTwo(false);
    //const OpenConnectionReplyOne = @import("../packets/open-connection-reply-one.zig");
    const common = @import("../packets/common.zig");

    var reader: Reader = .init(buffer, 0);

    const writer_buffer = try self.frame_pool.create(self.allocator);
    defer self.frame_pool.destroy(writer_buffer);

    var writer: Writer = .init(writer_buffer, 0);
    const packet_id: PacketId = .from(try reader.readByte());

    switch (packet_id) {
        .UnconnectedPing => {
            var packet: UnconnectedPingPacket = undefined;
            try common.read(UnconnectedPingPacket, &reader, &packet);

            try writer.writeByte(@intFromEnum(UnconnectedPongPacket.PacketId));
            try common.write(UnconnectedPongPacket, &writer, &.{
                .ping_time = packet.ping_time,
                .server_guid = self.guid,
                .motd = self.motd,
            });
            try endpoint.source.send(self.io, &endpoint.address, writer.getProcessedBytes());
        },
        .OpenConnectionRequestOne => {
            var packet: OpenConnectionRequestOne = undefined;
            try common.read(OpenConnectionRequestOne, &reader, &packet);

            // This should equal the total size
            std.debug.assert(packet.padding.length + 1 + 16 + 1 == reader.buffer.len);

            try writer.writeByte(@intFromEnum(OpenConnectionReplyOne.PacketId));
            try common.write(OpenConnectionReplyOne, &writer, &.{
                .server_guid = self.guid,
                .security = null,
                .mtu_size = @min(@as(u16, @intCast(reader.buffer.len + UDP_HEADER_SIZE)), MAX_MTU_SIZE), // packet id, magic, version, udp header
            });

            try endpoint.source.send(self.io, &endpoint.address, writer.getProcessedBytes());
        },
        .OpenConnectionRequestTwo => {
            var packet: OpenConnectionRequestTwoSafeless = undefined;
            try common.read(OpenConnectionRequestTwoSafeless, &reader, &packet);

            std.log.info("OpenConnectionRequestTwo mtu: {d}, client_guid: {d}", .{ packet.mtu, packet.client_guid });
        },
        else => {
            std.log.err("Unsupported packet: {s}, size: {d}, packet_id: {d}", .{ @tagName(packet_id), writer.buffer.len, writer.buffer[0] });
        },
    }
}
