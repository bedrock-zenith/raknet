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

pub const ONLINE_DATAGRAM_BIT_MASK = DATAGRAM_BIT_MASK | ACKNOWLEDGE_BIT_MASK | NOT_ACKNOWLEDGE_BIT_MASK;

pub const ACKNOWLEDGE_BIT_MASK = @import("acknowledge.zig").BIT_MASK;
pub const ACKNOWLEDGE_PACKED_ID = @import("acknowledge.zig").PACKED_ID;
pub const DATAGRAM_BIT_MASK = @import("datagram.zig").BIT_MASK;
pub const DATAGRAM_HEADER_SIZE = @import("datagram.zig").DATAGRAM_HEADER_SIZE;
pub const DatagramMemory = @import("datagram.zig").DatagramMemory;
pub const NOT_ACKNOWLEDGE_BIT_MASK = @import("not-acknowledge.zig").BIT_MASK;
pub const NOT_ACKNOWLEDGE_PACKED_ID = @import("not-acknowledge.zig").PACKED_ID;
pub const Segment = @import("datagram.zig").Segment;
