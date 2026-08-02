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

pub const MAX_MTU_SIZE = 1400; // Tested from BDS
pub const UDP_HEADER_SIZE = 28; // Tested from BDS, (MTU - received padded buffer.size)
pub const MIN_MTU = 576;
pub const MAX_MTU_FRAME_SIZE = 2048;
pub const STALE_CONNECTION_TIME_MS = 15_000;

pub const SYSTEM_ADDRESS_COUNT = 20;

// How many frames might be unacknownledged at the same time
// constant gathered from testing vanilla fork of raknet
// !!! In relations with other baked in constants, do not change!!!
pub const UNACKNOWLEDGED_WINDOWS_SIZE = 512;

pub const RAKNET_PROTOCOL_VERSION = 11;
