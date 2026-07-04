const std = @import("std");
const Endpoint = @import("../common/endpoint.zig");
const Dispatcher = @import("../common/dispatcher.zig").Dispatcher;
const Reader = @import("../common/cursor.zig").Reader;
const Writer = @import("../common/cursor.zig").Writer;
const PacketId = @import("../packets/packet-id.zig").PacketId;
const meta = @import("../common/meta.zig");
const offline_packets = @import("../packets/offline/root.zig");

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
const CandidatesDictionary = std.AutoHashMap(u32, ServerConnection);
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
candidates: CandidatesDictionary,
connections: ConnectionsDictionary,
frame_pool: FramePool,
onConnected: ConnectionEvent,
onDisconnected: ConnectionEvent,
onMessage: MessageEvent,
motd: []const u8,
secret_key: [16]u8,

pub fn init(io: std.Io, allocator: std.mem.Allocator) !Listener {
    var xiro = std.Random.Xoroshiro128.init(undefined);
    var listener: Listener = .{
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
        .secret_key = undefined,
    };
    try std.Io.randomSecure(io, &listener.secret_key);
    return listener;
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
    self.offline(buffer, endpoint);
}

fn offline(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) void {
    if (buffer.len == 0) return;

    const packet_id: PacketId = .from(buffer[0]);
    (switch (packet_id) {
        .UnconnectedPing => handleUnconnectedPing(self, buffer, endpoint),
        .OpenConnectionRequestOne => handleOpenConnectionOne(self, buffer, endpoint),
        .OpenConnectionRequestTwo => handleOpenConnectionTwo(self, buffer, endpoint),
        .DisconnectionNotification => {},
        _ => std.log.err("Unknown size: {d}, packet_id: {d}", .{ buffer.len, buffer[0] }),
        else => std.log.err("Unsupported packet: {s}, size: {d}, packet_id: {d}", .{ @tagName(packet_id), buffer.len, buffer[0] }),
    }) catch
        std.debug.print("debug: Failed process {s}", .{@tagName(packet_id)});
}

fn handleUnconnectedPing(self: *const Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    const UnconnectedPingPacket = offline_packets.UnconnectedPing;
    const UnconnectedPongPacket = offline_packets.UnconnectedPong;

    var writer_buffer: [1024]u8 = undefined;
    var writer: Writer = .init(&writer_buffer, 0);
    var reader: Reader = .init(buffer, 1);

    var packet: UnconnectedPingPacket = undefined;
    try meta.read(UnconnectedPingPacket, &reader, &packet);

    try writer.writeByte(@intFromEnum(UnconnectedPongPacket.PacketId));
    try meta.write(UnconnectedPongPacket, &writer, &.{
        .ping_time = packet.ping_time,
        .server_guid = self.guid,
        .motd = self.motd,
    });
    try endpoint.source.send(self.io, &endpoint.address, writer.getProcessedBytes());
}

fn handleOpenConnectionOne(self: *const Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    const OpenConnectionRequestOne = offline_packets.OpenConnectionRequestOne;
    const OpenConnectionReplyOne = offline_packets.OpenConnectionReplyOne;

    var writer_buffer: [1024]u8 = undefined;
    var writer: Writer = .init(&writer_buffer, 0);
    var reader: Reader = .init(buffer, 1);

    var packet: OpenConnectionRequestOne = undefined;
    try meta.read(OpenConnectionRequestOne, &reader, &packet);

    std.debug.assert(packet.padding.length + 1 + 16 + 1 == reader.buffer.len);

    // gen the damn cookie!!!
    var sip: std.hash.SipHash64(1, 3) = .init(&self.secret_key);
    sip.update(std.mem.asBytes(&endpoint.address));

    try writer.writeByte(@intFromEnum(OpenConnectionReplyOne.PacketId));
    try meta.write(OpenConnectionReplyOne, &writer, &.{
        .server_guid = self.guid,
        .security = @intCast(sip.finalInt() & 0xFFFFFFFF),
        .mtu_size = @min(@as(u16, @intCast(reader.buffer.len + UDP_HEADER_SIZE)), MAX_MTU_SIZE), // packet id, magic, version, udp header
    });

    try endpoint.source.send(self.io, &endpoint.address, writer.getProcessedBytes());
}

fn handleOpenConnectionTwo(self: *const Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    const OpenConnectionRequestTwo = offline_packets.OpenConnectionRequestTwo;
    const OpenConnectionReplyTwo = offline_packets.OpenConnectionReplyTwo;

    var writer_buffer: [1024]u8 = undefined;
    var writer: Writer = .init(&writer_buffer, 0);
    var reader: Reader = .init(buffer, 1);

    var packet: OpenConnectionRequestTwo = undefined;
    try meta.read(OpenConnectionRequestTwo, &reader, &packet);

    try writer.writeByte(@intFromEnum(OpenConnectionReplyTwo.PacketId));
    try meta.write(OpenConnectionReplyTwo, &writer, &.{
        .client_address = endpoint.address,
        .mtu_size = packet.mtu,
        .server_guid = self.guid,
    });

    try endpoint.source.send(self.io, &endpoint.address, writer.getProcessedBytes());
}
