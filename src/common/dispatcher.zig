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

pub const Context = ?*anyopaque;

pub fn Dispatcher(comptime EventData: type) type {
    return struct {
        pub const empty: @This() = .{
            .context = null,
            .callback = null,
        };

        pub const FnPtr = ?*const (fn (context: Context, event_data: EventData) void);
        pub const DataType = EventData;
        context: Context,
        callback: FnPtr,

        pub fn register(
            this: *@This(),
            comptime T: type,
            callback: ?*const (fn (context: T, event_data: EventData) void),
            context: T,
        ) void {
            this.context = @ptrCast(context);
            this.callback = @ptrCast(callback);
        }

        pub fn invoke(this: *const @This(), data: EventData) bool {
            if (this.callback) |fnc| {
                fnc(this.context, data);
                return true;
            }
            return false;
        }
    };
}

test "Dispatcher Test" {
    const Handler = Dispatcher(u32);
    var event: Handler = .empty;
    event.register(null, testFunc);
    _ = event.invoke(654);
}

fn testFunc(_: Context, value: u32) void {
    @import("std").testing.expectEqual(value, 654) catch unreachable;
}
