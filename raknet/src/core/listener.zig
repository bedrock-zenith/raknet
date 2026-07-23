const std = @import("std");

const common = @import("../common/root.zig");
const meta = common.binary;
const Reader = common.Reader;
const Writer = common.Writer;
const CONSTANTS = @import("../constants.zig");
const raknet = @import("../protocol/root.zig");
const IpAddress = raknet.RakAddress.Type;
const PacketId = raknet.PacketId;
const offline_packet = @import("../protocol/root.zig").offline;
pub const ClientSession = @import("client-session.zig");
const Endpoint = @import("endpoint.zig");
const FramePool = @import("root.zig").FramePool;
pub const ListenerEvent = @import("server-events.zig").ListenerEvent;

const Listener = @This();
const ListenerEventQueue = std.Deque(ListenerEvent);

guid: u64,
io: *const std.Io,
allocator: std.mem.Allocator,
sessions: std.AutoHashMap(IpAddress, *ClientSession),
pool_allocator: FramePool,
motd: []const u8,
secret_key: [16]u8,
server_events: ListenerEventQueue,

pub fn init(self: *Listener, io: *const std.Io, allocator: std.mem.Allocator) !void {
    var xiro = std.Random.Xoroshiro128.init(undefined);
    self.* = .{
        .io = io,
        .allocator = allocator,
        .guid = xiro.next(),
        .sessions = .init(allocator),
        .pool_allocator = try .init(allocator), // 131072
        .motd = "",
        .secret_key = undefined,
        .server_events = undefined,
    };
    self.server_events = try .initCapacity(allocator, 128);
    errdefer self.server_events.deinit(allocator);
    try std.Io.randomSecure(io.*, &self.secret_key);
}

pub fn optimze(self: *Listener) void {
    self.frame_pool.pool.reset(self.allocator, .{ .retain_with_limit = 64 });
}

pub fn deinit(self: *Listener) void {
    self.server_events.deinit(self.allocator);
    self.frame_pool.deinit(self.allocator);

    var iterator = self.sessions.valueIterator();
    while (iterator.next()) |value| {
        value.*.deinit();
        self.allocator.free(value.*);
    }
    self.sessions.deinit();
}

pub fn receive(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) void {
    if (buffer.len == 0) return;

    const packetId = buffer[0];
    if (packetId & raknet.datagram.ONLINE_DATAGRAM_BIT_MASK != 0)
        self.online(buffer, endpoint)
    else
        self.offline(buffer, endpoint);
}

pub inline fn dequeueEvent(self: *Listener) ?ListenerEvent {
    return self.server_events.popFront();
}

pub fn returnEvent(self: *Listener, event: ListenerEvent) void {
    switch (event) {
        .message => |message| {
            @import("connection.zig").destroySegment(self.pool_allocator, message.context);
        },
        .disconnection => |message| {
            message.connection.deinit();
        },
    }
}

pub fn tick(self: *Listener, current_tick: usize) !void {
    var iterator = self.sessions.valueIterator();
    while (iterator.next()) |session| {
        try session.*.tick(current_tick);
    }
}

fn online(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) void {
    if (self.sessions.get(endpoint.address)) |connection| {
        connection.receive(buffer) catch unreachable;
    }
}

fn offline(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) void {
    const packet_id: PacketId = .from(buffer[0]);
    (switch (packet_id) {
        .UnconnectedPing => rxUnconnectedPing(self, buffer, endpoint),
        .OpenConnectionRequestOne => rxOpenConnectionOne(self, buffer, endpoint),
        .OpenConnectionRequestTwo => rxOpenConnectionTwo(self, buffer, endpoint),
        .DisconnectionNotification => {
            if (self.sessions.getEntry(endpoint.address)) |entry| {
                if (entry.value_ptr.*.*.connection.state == .Unconnected)
                    self.sessions.removeByPtr(entry.key_ptr);
            }
        },
        _ => std.log.err("Unknown packet, size: {d}, packet_id: {d}", .{ buffer.len, buffer[0] }),
        else => std.log.err("Unsupported packet: {s}, size: {d}, packet_id: {d}", .{ @tagName(packet_id), buffer.len, buffer[0] }),
    }) catch
        std.debug.print("debug: Failed process {s}", .{@tagName(packet_id)});
}

fn rxUnconnectedPing(self: *const Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    const packet = try readPacket(buffer, offline_packet.UnconnectedPing);
    try sendPacket(self, endpoint, offline_packet.UnconnectedPong, &.{
        .ping_time = packet.ping_time,
        .server_guid = self.guid,
        .motd = self.motd,
    });
}

fn rxOpenConnectionOne(self: *const Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    if (self.sessions.get(endpoint.address)) |connection| {
        try sendPacket(self, endpoint, offline_packet.AlreadyConnected, &.{
            .client_guid = connection.connection.guid,
        });
        return;
    }

    const packet = try readPacket(buffer, offline_packet.OpenConnectionRequestOne);

    if (packet.protocol_version != CONSTANTS.RAKNET_PROTOCOL_VERSION) {
        try sendPacket(self, endpoint, offline_packet.IncompatibleProtocolVersion, &.{
            .server_guid = self.guid,
            .protocol_version = CONSTANTS.RAKNET_PROTOCOL_VERSION,
        });
        return;
    }

    std.debug.assert(packet.padding.length + 1 + 16 + 1 == buffer.len);
    try sendPacket(self, endpoint, offline_packet.OpenConnectionReplyOne, &.{
        .server_guid = self.guid,
        .security = self.genCookie(endpoint),
        .mtu_size = @as(u16, @intCast(buffer.len + CONSTANTS.UDP_HEADER_SIZE)), // packet id, magic, version, udp header
    });
}

fn rxOpenConnectionTwo(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) !void {
    if (self.sessions.get(endpoint.address)) |connection| {
        try sendPacket(self, endpoint, offline_packet.AlreadyConnected, &.{
            .client_guid = connection.connection.guid,
        });
        return;
    }

    const packet = try readPacket(buffer, offline_packet.OpenConnectionRequestTwo);
    const expected_cookie = self.genCookie(endpoint);

    if (packet.security.cookie != expected_cookie) {
        try sendPacket(self, endpoint, offline_packet.ConnectionAttemptFailed, &.{});
        return;
    }

    const new_mtu = @min(packet.mtu, CONSTANTS.MAX_MTU_SIZE);
    try sendPacket(self, endpoint, offline_packet.OpenConnectionReplyTwo, &.{
        .client_address = endpoint.address,
        .mtu_size = new_mtu,
        .server_guid = self.guid,
    });

    const client = try self.allocator.create(ClientSession);
    try client.init(
        self,
        endpoint,
        packet.client_guid,
        new_mtu,
    );

    try self.sessions.put(endpoint.address, client);
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

    try endpoint.source.send(self.io.*, &endpoint.address, writer.getProcessedBytes());
}

inline fn readPacket(buffer: []const u8, comptime T: type) !T {
    var reader: Reader = .init(buffer, 1);
    var packet: T = undefined;
    try meta.readAsserted(T, &reader, &packet);
    return packet;
}
