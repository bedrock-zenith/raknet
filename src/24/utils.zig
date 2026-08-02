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

const MAX_U24: u32 = @intCast(std.math.maxInt(u24));
const HALF_U24: u32 = @divTrunc(MAX_U24, 2);

pub inline fn fixed(number: u32) u32 {
    return number & MAX_U24;
}

test "fixed" {
    try std.testing.expectEqual(@as(u32, 1), fixed(0xFF_FFFF + 2));
}

pub inline fn overflowed(old: u32, new: u32) bool {
    return ((new -% old) & MAX_U24) >= HALF_U24;
}

pub inline fn distance(old: u32, new: u32) i32 {
    const diff = (new -% old) & MAX_U24;

    if (diff >= HALF_U24) {
        return @bitCast(diff -% 0x0100_0000);
    }

    return @bitCast(diff);
}

test "distance" {
    try std.testing.expectEqual(distance(0xFF_FFFF, 1), 2);
    try std.testing.expectEqual(distance(0, 0xFF_FFFF), -1);
}
