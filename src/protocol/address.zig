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

pub const Type = @import("std").Io.net.IpAddress;

const Cursor = @import("../common/cursor.zig");

pub fn deserialize(cursor: *Cursor.Reader, address: *Type) !void {
    try cursor.assert(1);
    const version = cursor.readByte();
    switch (version) {
        4 => {
            try cursor.assert(6);

            const addr: *const [4]u8 = cursor.readSlice(4)[0..4];
            const port: u16 = cursor.readInt(u16, .big);
            address.* = .{
                .ip4 = .{
                    .bytes = addr.*,
                    .port = port,
                },
            };
        },
        6 => {
            try cursor.assert(28);
            // Should be address family, and yes its little endian
            _ = cursor.readInt(u16, .little);
            const port: u16 = cursor.readInt(u16, .big);

            const flow: u32 = cursor.readInt(u32, .big);
            const addr: *const [16]u8 = cursor.readSlice(16)[0..16];
            const scopeId: u32 = cursor.readInt(u32, .big);

            address.* = .{ .ip6 = undefined };
            address.*.ip6 = .{
                .bytes = addr.*,
                .flow = flow,
                .port = port,
                .interface = .{ .index = scopeId },
            };
        },
        else => return error.UnsupportedIPVersion,
    }
}
pub fn serialize(cursor: *Cursor.Writer, address: *const Type) !void {
    switch (address.*) {
        .ip4 => |ip4| {
            try cursor.assert(7);

            cursor.writeByte(4);
            cursor.append(&ip4.bytes);
            cursor.writeInt(u16, ip4.port, .big);
        },
        .ip6 => |ip6| {
            try cursor.assert(29);

            cursor.writeByte(6);

            // Unknow InnerNetwrokIpv6Interface
            cursor.writeInt(u16, 0, .little);

            cursor.writeInt(u16, ip6.port, .big);
            cursor.writeInt(u32, ip6.flow, .big);
            cursor.append(&ip6.bytes);
            cursor.writeInt(u32, ip6.interface.index, .big);
        },
    }
}
