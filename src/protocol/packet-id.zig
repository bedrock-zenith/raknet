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

// -------- Enums --------
pub const PacketId = enum(u8) {
    pub fn from(num: u8) PacketId {
        return @enumFromInt(num);
    }
    UnconnectedPing = 0x01,
    UnconnectedPingOpenConnections = 0x02,
    UnconnectedPong = 0x1c,
    ConnectedPing = 0x00,
    ConnectedPong = 0x03,
    OpenConnectionRequestOne = 0x05,
    OpenConnectionReplyOne = 0x06,
    OpenConnectionRequestTwo = 0x07,
    OpenConnectionReplyTwo = 0x08,
    ConnectionRequest = 0x09,
    RemoteSystemRequiresPublicKey = 0x0a,
    OurSystemRequiresSecurity = 0x0b,
    ConnectionAttemptFailed = 0x11,
    AlreadyConnected = 0x12,
    ConnectionRequestAccepted = 0x10,
    NewIncomingConnection = 0x13,
    DisconnectionNotification = 0x15,
    ConnectionLost = 0x16,
    IncompatibleProtocolVersion = 0x19,
    GameData = 0xfe,
    _, // This could be unknown packet-type from future versions
};
