const std = @import("std");
const Dispatcher = @import("../common/dispatcher.zig").Dispatcher;

const Listener = @This();

pub const ServerConnection = struct {};
const IpAddress = std.Io.net.IpAddress;
const MIN_MTU = 576;
const MAX_MTU_FRAME_SIZE = 2048;
const STALE_CONNECTION_TIME_MS = 15_000;
const ConnectionsDictionary = struct {}; // std.HashMap(IpAddress, ServerConnection);
const FramePool = std.heap.MemoryPool([MAX_MTU_FRAME_SIZE]u8);
const ConnectionEvent = Dispatcher(ServerConnection); //
const MessageEvent = Dispatcher(struct {
    message: []const u8,
    connection: *const ServerConnection,
});

guid: u64,
io: std.Io,
socket: std.Io.net.Socket,
candidates: ConnectionsDictionary,
connections: ConnectionsDictionary,
frame_pool: FramePool,
onConnected: ConnectionEvent,
onDisconnected: ConnectionEvent,
onMessage: MessageEvent,

pub fn init(io: std.Io, allocator: std.mem.Allocator, socket: std.Io.net.Socket) !Listener {
    var xiro = std.Random.Xoroshiro128.init(undefined);
    return .{
        .io = io,
        .socket = socket,
        .guid = xiro.next(),
        .candidates = .{},
        .connections = .{},
        //.candidates = .{}, //.init(allocator),
        //.connections = .{}, //.init(allocator),
        .frame_pool = try .initCapacity(allocator, 64 * 64), // 8_388_608
        .onConnected = .empty,
        .onDisconnected = .empty,
        .onMessage = .empty,
    };
}

// common handler for any raw bytes coming in
pub fn receive(self: *Listener, buffer: []const u8, endpoint: *const std.Io.net.IpAddress) !void {
    if (true) try self.offline(buffer, endpoint);
}

// handle all offline packets
fn offline(self: *Listener, buffer: []const u8, endpoint: *const std.Io.net.IpAddress) !void {
    _ = self;
    _ = buffer;
    _ = endpoint;
}
