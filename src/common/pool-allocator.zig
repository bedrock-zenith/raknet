//  SPDX-License-Identifier: LGPL-3.0-or-later
//  ============================================================================
//   Zenith Raknet - Minecraft Bedrock Raknet
//   Copyright (C) 2026 Bedrock Zenith
//   https://github.com/bedrock-zenith/raknet
//  ============================================================================
//  
//  This file is part of Zenith Raknet.
//  
//  Zenith Raknet is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//  
//  Zenith Raknet is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Lesser General Public License for more details.
//  
//  You should have received a copy of the GNU Lesser General Public License
//  along with Zenith Raknet. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");

pub fn PoolAllocator(comptime POOL_SIZE: comptime_int) type {
    const Pool = std.heap.MemoryPoolExtra(
        [POOL_SIZE]u8,
        .{
            .alignment = .of(usize),
            .growable = true,
        },
    );

    return struct {
        pub const PAGE_SIZE = POOL_SIZE;
        backing_allocator: std.mem.Allocator,
        pool: Pool,

        pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!@This() {
            return .{
                .backing_allocator = allocator,
                .pool = (try Pool.initCapacity(allocator, 64)),
            };
        }

        pub inline fn deinit(self: *@This()) void {
            self.pool.deinit(self.backing_allocator);
        }

        pub inline fn create(self: *@This(), comptime T: type) std.mem.Allocator.Error!*T {
            if (@sizeOf(T) > POOL_SIZE)
                @compileError("Object too large, T:" ++ @typeName(T));
            if (@alignOf(T) > @alignOf(usize))
                @compileError("Alignment too large for " ++ @typeName(T));

            const ptr = try self.pool.create(self.backing_allocator);
            return @ptrCast(@alignCast(ptr));
        }

        pub inline fn rent(self: *@This()) std.mem.Allocator.Error!*[POOL_SIZE]u8 {
            return try self.pool.create(self.backing_allocator);
        }

        pub inline fn alloc(self: *@This(), comptime T: type) std.mem.Allocator.Error!*[@divExact(POOL_SIZE, @sizeOf(T))]T {
            if (@sizeOf(T) > POOL_SIZE)
                @compileError("Object too large, T:" ++ @typeName(T));
            if (@alignOf(T) > @alignOf(usize))
                @compileError("Alignment too large for " ++ @typeName(T));

            const ptr = try self.pool.create(self.backing_allocator);
            return @ptrCast(@alignCast(ptr));
        }

        pub inline fn remaining(_: *const @This(), comptime T: type, value: *T) []u8 {
            if (@sizeOf(T) > POOL_SIZE)
                @compileError("Object too large, T:" ++ @typeName(T));

            const ptr: [*]u8 = @ptrCast(value);
            return ptr[@sizeOf(T)..POOL_SIZE];
        }

        pub inline fn destroy(self: *@This(), v: *anyopaque) void {
            const block_ptr: *[POOL_SIZE]u8 = @ptrCast(v);
            self.pool.destroy(@alignCast(block_ptr));
        }
    };
}
