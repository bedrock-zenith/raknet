const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("../common/root.zig");
const meta = common.binary;
const Reader = common.Reader;
const Writer = common.Writer;
const CONSTANTS = @import("../constants.zig");
const raknet = @import("../protocol/root.zig");
const IpAddress = raknet.RakAddress.Type;
const PacketId = raknet.PacketId;
const offline_packet = @import("../protocol/root.zig").offline;
const logger = @import("../root.zig").raknet_logger;
pub const ClientSession = @import("client-session.zig");
const Endpoint = @import("endpoint.zig");
const FramePool = @import("root.zig").FramePool;
pub const ListenerEvent = @import("server-events.zig").ListenerEvent;

const Listener = @This();
const ListenerEventQueue = std.Deque(ListenerEvent);
guid: u64,
io: std.Io,
last_tick: usize,
allocator: Allocator,
sessions: std.AutoHashMap(IpAddress, *ClientSession),
pool_allocator: FramePool,
motd: []const u8,
secret_key: [16]u8,
server_events: ListenerEventQueue,
tx_send: std.Deque(struct { buffer: []u8, endpoint: Endpoint }),

pub fn init(self: *Listener, io: std.Io, allocator: Allocator) !void {
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
        .last_tick = 0,
        .tx_send = undefined,
    };

    self.server_events = try .initCapacity(allocator, 128);
    errdefer self.server_events.deinit(allocator);
    self.tx_send = try .initCapacity(allocator, 32);
    errdefer self.tx_send.deinit(allocator);
    try std.Io.randomSecure(io, &self.secret_key);
}

pub fn optimze(self: *Listener) void {
    self.frame_pool.pool.reset(self.allocator, .{ .retain_with_limit = 64 });
}

pub fn deinit(self: *Listener) void {
    // server events
    {
        var iterator = self.server_events.iterator();
        while (iterator.next()) |event|
            returnEvent(self, event);

        self.server_events.deinit(self.allocator);
    }

    // sessions
    {
        var iterator = self.sessions.valueIterator();
        while (iterator.next()) |value| {
            value.*.deinit();
            self.allocator.destroy(value.*);
        }
        self.sessions.deinit();
    }

    while (self.tx_send.popFront()) |info|
        self.pool_allocator.destroy(info.buffer.ptr);

    self.tx_send.deinit(self.allocator);

    // should be final
    self.pool_allocator.deinit();
}

pub fn receive(self: *Listener, buffer: []const u8, endpoint: *const Endpoint, current_tick: usize) Allocator.Error!void {
    self.last_tick = current_tick; // autofix
    if (buffer.len == 0) return;

    const packetId = buffer[0];
    if (packetId & raknet.datagram.ONLINE_DATAGRAM_BIT_MASK != 0)
        try self.online(buffer, endpoint)
    else
        try self.offline(buffer, endpoint);
}

pub inline fn dequeueEvent(self: *Listener) ?ListenerEvent {
    return self.server_events.popFront();
}

pub fn returnEvent(self: *Listener, event: ListenerEvent) void {
    switch (event) {
        .messaged => |message| {
            @import("connection.zig").destroySegment(&self.pool_allocator, self.pool_allocator.backing_allocator, @ptrCast(@alignCast(@constCast(message.context))));
        },
        .disconnected => |message| {
            message.session.deinit();
        },
        .connected => {},
    }
}

pub fn tick(self: *Listener, current_tick: usize) Allocator.Error!void {
    var sessions_to_remove: [16]*ClientSession = undefined;
    var sessions_count: usize = 0;
    self.last_tick = current_tick;
    var iterator = self.sessions.valueIterator();
    while (iterator.next()) |s| {
        const session = s.*;
        if (session.connection.state == .Disconnected) {
            @branchHint(.unlikely);
            if (sessions_count < sessions_to_remove.len) {
                @branchHint(.likely);
                sessions_to_remove[sessions_count] = session;
                sessions_count += 1;
            }
            continue;
        }
        try session.tick(current_tick);
    }

    while (sessions_count > 0) {
        @branchHint(.unlikely);
        sessions_count -%= 1;
        _ = self.sessions.remove(sessions_to_remove[sessions_count].connection.endpoint.address);
    }
}

pub fn txFlush(self: *Listener) std.Io.net.Socket.SendError!void {
    while (self.tx_send.popFront()) |info| {
        try info.endpoint.send(self.io, info.buffer);
        self.pool_allocator.destroy(info.buffer.ptr);
    }

    var iterator = self.sessions.valueIterator();
    while (iterator.next()) |session| {
        try session.*.txFlush();
    }
}

fn online(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) Allocator.Error!void {
    if (self.sessions.get(endpoint.address)) |connection| {
        try connection.receive(buffer);
    }
}

fn offline(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) Allocator.Error!void {
    const packet_id: PacketId = .from(buffer[0]);
    try switch (packet_id) {
        .UnconnectedPing => rxUnconnectedPing(self, buffer, endpoint),
        .OpenConnectionRequestOne => rxOpenConnectionOne(self, buffer, endpoint),
        .OpenConnectionRequestTwo => rxOpenConnectionTwo(self, buffer, endpoint),
        .DisconnectionNotification => {
            if (self.sessions.getEntry(endpoint.address)) |entry| {
                if (entry.value_ptr.*.*.connection.state == .Unconnected)
                    self.sessions.removeByPtr(entry.key_ptr);
            }
        },
        _ => logger.err("Unknown packet, size: {d}, packet_id: {d}", .{ buffer.len, buffer[0] }),
        else => logger.err("Unsupported packet: {s}, size: {d}, packet_id: {d}", .{ @tagName(packet_id), buffer.len, buffer[0] }),
    };
}

fn rxUnconnectedPing(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) Allocator.Error!void {
    // Lets just return if we fail to parse the packet
    const packet = readPacket(buffer, offline_packet.UnconnectedPing) catch return;
    try sendOfflinePacket(self, endpoint, offline_packet.UnconnectedPong, &.{
        .ping_time = packet.ping_time,
        .server_guid = self.guid,
        .motd = self.motd,
    });
}

fn rxOpenConnectionOne(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) Allocator.Error!void {
    if (self.sessions.get(endpoint.address)) |connection| {
        try sendOfflinePacket(self, endpoint, offline_packet.AlreadyConnected, &.{
            .client_guid = connection.connection.guid,
        });
        return;
    }

    // Lets just return if we fail to parse the packet
    const packet = readPacket(buffer, offline_packet.OpenConnectionRequestOne) catch return;

    if (packet.protocol_version != CONSTANTS.RAKNET_PROTOCOL_VERSION) {
        try sendOfflinePacket(self, endpoint, offline_packet.IncompatibleProtocolVersion, &.{
            .server_guid = self.guid,
            .protocol_version = CONSTANTS.RAKNET_PROTOCOL_VERSION,
        });
        return;
    }

    std.debug.assert(packet.padding.length + 1 + 16 + 1 == buffer.len);
    try sendOfflinePacket(self, endpoint, offline_packet.OpenConnectionReplyOne, &.{
        .server_guid = self.guid,
        .security = self.genCookie(endpoint),
        .mtu_size = @as(u16, @intCast(buffer.len + CONSTANTS.UDP_HEADER_SIZE)), // packet id, magic, version, udp header
    });
}

fn rxOpenConnectionTwo(self: *Listener, buffer: []const u8, endpoint: *const Endpoint) Allocator.Error!void {
    if (self.sessions.get(endpoint.address)) |connection| {
        try sendOfflinePacket(self, endpoint, offline_packet.AlreadyConnected, &.{
            .client_guid = connection.connection.guid,
        });
        return;
    }

    // Lets just return if we fail to parse the packet
    const packet = readPacket(buffer, offline_packet.OpenConnectionRequestTwo) catch return;
    const expected_cookie = self.genCookie(endpoint);

    if (packet.security.cookie != expected_cookie) {
        try sendOfflinePacket(self, endpoint, offline_packet.ConnectionAttemptFailed, &.{});
        return;
    }

    const new_mtu = @min(packet.mtu, CONSTANTS.MAX_MTU_SIZE);
    try sendOfflinePacket(self, endpoint, offline_packet.OpenConnectionReplyTwo, &.{
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

inline fn sendOfflinePacket(self: *Listener, endpoint: *const Endpoint, comptime T: type, value: *const T) Allocator.Error!void {
    const buffer = try self.pool_allocator.rent();
    errdefer self.pool_allocator.destroy(buffer.ptr);
    var writer: Writer = .init(buffer, 0);
    writer.writeByte(@intFromEnum(T.PacketId));

    meta.writeAsserted(T, &writer, value) catch return;

    try self.tx_send.pushBack(self.allocator, .{ .buffer = buffer, .endpoint = endpoint.* });
}

inline fn readPacket(buffer: []const u8, comptime T: type) !T {
    var reader: Reader = .init(buffer, 1);
    var packet: T = undefined;
    try meta.readAsserted(T, &reader, &packet);
    return packet;
}
