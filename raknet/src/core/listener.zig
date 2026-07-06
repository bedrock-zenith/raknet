const std = @import("std");
const IpAddress = std.Io.net.IpAddress;
const Endpoint = @import("../common/endpoint.zig");
const Dispatcher = @import("../common/dispatcher.zig").Dispatcher;
const Reader = @import("../common/cursor.zig").Reader;
const Writer = @import("../common/cursor.zig").Writer;
const PacketId = @import("../packets/packet-id.zig").PacketId;
const meta = @import("../common/meta.zig");
const offline_packets = @import("../packets/offline/root.zig");
const well_known = @import("./well-known.zig");

const Listener = @This();

pub const IpAddressIndexContext = struct {
    pub fn eql(_: @This(), a: IpAddress, b: IpAddress) bool {
        return a.eql(&b);
    }
    pub fn hash(_: @This(), key: IpAddress) u64 {
        return std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
    }
};

const ConnectionsDictionary = std.AutoHashMap(IpAddress, ServerConnection);
const FramePool = std.heap.MemoryPool([well_known.MAX_MTU_FRAME_SIZE]u8);
pub const ConnectionEvent = Dispatcher(ServerConnection);
pub const MessageEvent = Dispatcher(struct {
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

pub fn receive(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) void {
    if (buffer.len == 0) return;

    const packetId = buffer[0];
    if (packetId & well_known.ONLINE_DATAGRAM_BIT_MASK != 0)
        self.online(buffer, endpoint)
    else
        self.offline(buffer, endpoint);
}

fn online(_: *Listener, _: []const u8, _: *const Endpoint) void {
    std.log.info("Online packet received!", .{});
}

fn offline(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) void {
    const packet_id: PacketId = .from(buffer[0]);
    //std.log.info("offline: {}", .{buffer[0]});
    (switch (packet_id) {
        .UnconnectedPing => handleUnconnectedPing(self, buffer, endpoint),
        .OpenConnectionRequestOne => handleOpenConnectionOne(self, buffer, endpoint),
        .OpenConnectionRequestTwo => handleOpenConnectionTwo(self, buffer, endpoint),
        .DisconnectionNotification => {},
        _ => std.log.err("Unknown packet, size: {d}, packet_id: {d}", .{ buffer.len, buffer[0] }),
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
    const IncompatibleProtocolVersion = offline_packets.IncompatibleProtocolVersion;

    var writer_buffer: [1024]u8 = undefined;
    var writer: Writer = .init(&writer_buffer, 0);
    var reader: Reader = .init(buffer, 1);

    var packet: OpenConnectionRequestOne = undefined;
    try meta.read(OpenConnectionRequestOne, &reader, &packet);

    if (packet.protocol_version != well_known.RAKNET_PROTOCOL_VERSION) {
        try writer.writeByte(@intFromEnum(IncompatibleProtocolVersion.PacketId));
        try meta.write(IncompatibleProtocolVersion, &writer, &.{
            .server_guid = self.guid,
            .protocol_version = well_known.RAKNET_PROTOCOL_VERSION,
        });
    } else {
        std.debug.assert(packet.padding.length + 1 + 16 + 1 == reader.buffer.len);
        try writer.writeByte(@intFromEnum(OpenConnectionReplyOne.PacketId));
        try meta.write(OpenConnectionReplyOne, &writer, &.{
            .server_guid = self.guid,
            .security = self.genCookie(endpoint),
            .mtu_size = @min(@as(u16, @intCast(reader.buffer.len + well_known.UDP_HEADER_SIZE)), well_known.MAX_MTU_SIZE), // packet id, magic, version, udp header
        });
    }

    try endpoint.source.send(self.io, &endpoint.address, writer.getProcessedBytes());
}

fn handleOpenConnectionTwo(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    const OpenConnectionRequestTwo = offline_packets.OpenConnectionRequestTwo;
    const OpenConnectionReplyTwo = offline_packets.OpenConnectionReplyTwo;

    var writer_buffer: [1024]u8 = undefined;
    var writer: Writer = .init(&writer_buffer, 0);
    var reader: Reader = .init(buffer, 1);

    var packet: OpenConnectionRequestTwo = undefined;
    try meta.read(OpenConnectionRequestTwo, &reader, &packet);

    const expected_cookie = self.genCookie(endpoint);
    if (packet.security.cookie != expected_cookie) return;

    try writer.writeByte(@intFromEnum(OpenConnectionReplyTwo.PacketId));
    try meta.write(OpenConnectionReplyTwo, &writer, &.{
        .client_address = endpoint.address,
        .mtu_size = packet.mtu,
        .server_guid = self.guid,
    });

    try endpoint.source.send(self.io, &endpoint.address, writer.getProcessedBytes());

    try self.candidates.put(endpoint.address, .{});
}

fn genCookie(self: *const Listener, endpoint: *const Endpoint) u32 {
    var sip: std.hash.SipHash64(1, 3) = .init(&self.secret_key);
    // we switch on underlying data type as whole union has different padding for smaller types,
    // so it might contain undefined bytes inside the hash,
    // and the hash becomes non deterministic
    switch (endpoint.address) {
        .ip4 => |ip4| sip.update(std.mem.asBytes(&ip4)),
        .ip6 => |ip6| sip.update(std.mem.asBytes(&ip6)),
    }
    return @intCast(sip.finalInt() & 0xffff_ffff);
}
