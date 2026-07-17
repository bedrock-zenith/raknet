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
