const std = @import("std");
const Listener = @This();
const IpAddress = std.Io.net.IpAddress;
const MIN_MTU = 576;
const MAX_MTU_FRAME_SIZE = 2048;
const STALE_CONNECTION_TIME_MS = 15_000;
const ConnectionsDictionary = std.HashMap(IpAddress, void);
const FramePool = std.heap.MemoryPool([MAX_MTU_FRAME_SIZE]u8);

guid: u64,
io: std.Io,
socket: std.Io.net.Socket,
candidates: ConnectionsDictionary,
connections: ConnectionsDictionary,
frame_pool: FramePool,

pub fn init(io: std.Io, allocator: std.mem.Allocator, socket: std.Io.net.Socket) Listener {
    return .{
        .io = io,
        .socket = socket,
        .guid = std.Random.Xoroshiro128.init(undefined).next(),
        .candidates = .init(allocator),
        .connections = .init(allocator),
        .frame_pool = .initCapacity(allocator, 64 * 64), // 8_388_608
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
