const std = @import("std");
const IpAddress = std.Io.net.IpAddress;

const Reader = @import("../common/cursor.zig").Reader;
const Writer = @import("../common/cursor.zig").Writer;
const Dispatcher = @import("../common/dispatcher.zig").Dispatcher;
const Endpoint = @import("../common/endpoint.zig");
const meta = @import("../common/meta.zig");
const offline_packets = @import("../packets/offline/root.zig");
const PacketId = @import("../packets/packet-id.zig").PacketId;
pub const ServerConnection = @import("./client-connection.zig");
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

const ConnectionsDictionary = std.AutoHashMap(IpAddress, *ServerConnection);
const FramePool = std.heap.MemoryPool([well_known.MAX_MTU_FRAME_SIZE]u8);
pub const ConnectionEvent = Dispatcher(*ServerConnection);
pub const MessageEvent = Dispatcher(struct {
    message: []const u8,
    connection: *const ServerConnection,
});

guid: u64,
io: std.Io,
allocator: std.mem.Allocator,
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

    var iterator = self.connections.valueIterator();
    while (iterator.next()) |value| {
        value.*.deinit();
        self.allocator.free(value.*);
    }
    self.connections.deinit();
}

pub fn receive(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) void {
    if (buffer.len == 0) return;

    const packetId = buffer[0];
    if (packetId & well_known.ONLINE_DATAGRAM_BIT_MASK != 0)
        self.online(buffer, endpoint)
    else
        self.offline(buffer, endpoint);
}

fn online(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) void {
    std.log.info("Online packet received!", .{});

    if (self.connections.get(endpoint.address)) |connection| {
        connection.*.base_connection.handle(buffer) catch {};
    }
}

fn offline(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) void {
    const packet_id: PacketId = .from(buffer[0]);
    (switch (packet_id) {
        .UnconnectedPing => handleUnconnectedPing(self, buffer, endpoint),
        .OpenConnectionRequestOne => handleOpenConnectionOne(self, buffer, endpoint),
        .OpenConnectionRequestTwo => handleOpenConnectionTwo(self, buffer, endpoint),
        .DisconnectionNotification => {
            if (self.connections.getEntry(endpoint.address)) |entry| {
                if (entry.value_ptr.*.*.base_connection.connection_state == .Unconnected)
                    self.connections.removeByPtr(entry.key_ptr);
            }
        },
        _ => std.log.err("Unknown packet, size: {d}, packet_id: {d}", .{ buffer.len, buffer[0] }),
        else => std.log.err("Unsupported packet: {s}, size: {d}, packet_id: {d}", .{ @tagName(packet_id), buffer.len, buffer[0] }),
    }) catch
        std.debug.print("debug: Failed process {s}", .{@tagName(packet_id)});
}

fn handleUnconnectedPing(self: *const Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    const packet = try readPacket(buffer, offline_packets.UnconnectedPing);
    try sendPacket(self, endpoint, offline_packets.UnconnectedPong, &.{
        .ping_time = packet.ping_time,
        .server_guid = self.guid,
        .motd = self.motd,
    });
}

fn handleOpenConnectionOne(self: *const Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    if (self.connections.get(endpoint.address)) |connection| {
        try sendPacket(self, endpoint, offline_packets.AlreadyConnected, &.{
            .client_guid = connection.base_connection.guid,
        });
        return;
    }

    const packet = try readPacket(buffer, offline_packets.OpenConnectionRequestOne);

    if (packet.protocol_version != well_known.RAKNET_PROTOCOL_VERSION) {
        try sendPacket(self, endpoint, offline_packets.IncompatibleProtocolVersion, &.{
            .server_guid = self.guid,
            .protocol_version = well_known.RAKNET_PROTOCOL_VERSION,
        });
        return;
    }

    std.debug.assert(packet.padding.length + 1 + 16 + 1 == buffer.len);
    try sendPacket(self, endpoint, offline_packets.OpenConnectionReplyOne, &.{
        .server_guid = self.guid,
        .security = self.genCookie(endpoint),
        .mtu_size = @min(@as(u16, @intCast(buffer.len + well_known.UDP_HEADER_SIZE)), well_known.MAX_MTU_SIZE), // packet id, magic, version, udp header
    });
}

fn handleOpenConnectionTwo(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    if (self.connections.get(endpoint.address)) |connection| {
        try sendPacket(self, endpoint, offline_packets.AlreadyConnected, &.{
            .client_guid = connection.base_connection.guid,
        });
        return;
    }

    const packet = try readPacket(buffer, offline_packets.OpenConnectionRequestTwo);
    const expected_cookie = self.genCookie(endpoint);

    if (packet.security.cookie != expected_cookie) {
        try sendPacket(self, endpoint, offline_packets.ConnectionAttemptFailed, &.{});
        return;
    }

    try sendPacket(self, endpoint, offline_packets.OpenConnectionReplyTwo, &.{
        .client_address = endpoint.address,
        .mtu_size = packet.mtu,
        .server_guid = self.guid,
    });

    const client = try self.allocator.create(ServerConnection);
    client.* = .init(endpoint, packet.client_guid);

    try self.connections.put(endpoint.address, client);
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

inline fn sendPacket(self: *const Listener, endpoint: *const Endpoint, comptime T: type, value: *const T) !void {
    var writer_buffer: [1024]u8 = undefined;
    var writer: Writer = .init(&writer_buffer, 0);
    writer.writeByte(@intFromEnum(T.PacketId));
    try meta.writeAsserted(T, &writer, value);

    try endpoint.source.send(self.io, &endpoint.address, writer.getProcessedBytes());
}

inline fn readPacket(buffer: []const u8, comptime T: type) !T {
    var reader: Reader = .init(buffer, 1);
    var packet: T = undefined;
    try meta.readAsserted(T, &reader, &packet);
    return packet;
}
