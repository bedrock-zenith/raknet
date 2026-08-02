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

const Utils = @import("utils.zig");

pub fn Window(comptime T: type, comptime range: comptime_int) type {
    comptime {
        if (!std.math.isPowerOfTwo(range))
            @compileError("range must be a power of two.");
    }

    return struct {
        const Self = @This();
        pub const RANGE: u32 = range;
        pub const RANGE_MASK: u32 = RANGE - 1;

        head: u32 = 0,
        tail: u32 = 0,
        len: usize = 0,
        buffer: [RANGE]T,

        pub inline fn clear(self: *Self) void {
            self.tail = self.head;
            self.len = 0;
        }

        pub inline fn available(self: *const Self) u32 {
            return @intCast(RANGE - self.len);
        }

        pub inline fn includes(self: *const Self, index: u32) bool {
            return Utils.distance(self.tail, index) >= 0 and Utils.distance(self.head, index) < 0;
        }

        pub inline fn push(self: *Self, value: T) u32 {
            std.debug.assert(available(self) > 0);
            const index = self.head;
            self.buffer[index % RANGE] = value;
            self.head = Utils.fixed(index +% 1);
            return index;
        }

        pub inline fn peek(self: *const Self) T {
            std.debug.assert(available(self) > 0);
            return self.buffer[self.tail % RANGE];
        }

        pub inline fn pop(self: *Self) T {
            const v = peek(self);
            self.tail = Utils.fixed(self.tail +% 1);
            return v;
        }

        pub inline fn iterator(self: *const Self) Iterator {
            return .{
                .ref = self,
                .curr_seq = self.tail,
                .remaining = @intCast(self.len),
            };
        }

        pub const Iterator = struct {
            ref: *const Self,
            curr_seq: u32,
            remaining: u32,

            pub fn next(self: *Iterator) ?T {
                if (self.remaining == 0) return null;

                const value = self.ref.buffer[self.curr_seq % self.ref.buffer.len];
                self.remaining -= 1;
                self.curr_seq = Utils.fixed(self.curr_seq +% 1);

                return value;
            }
        };
    };
}
