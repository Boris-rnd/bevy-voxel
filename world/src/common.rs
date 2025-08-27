use crate::*;
use super::*;

/// Represents a position in the local coordinate system of a chunk
/// Every coordinate is in the range [0, 3]
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq)]
pub struct LocalPos {
    // 6 bits used
    pub idx: u32,
}
impl LocalPos {
    #[track_caller]
    pub fn new(x: u32, y: u32, z: u32) -> Self {
        assert!(
            x < CHUNK_SIZE as u32 && y < CHUNK_SIZE as u32 && z < CHUNK_SIZE as u32,
            "Local position out of bounds: {}, {}, {}",
            x,
            y,
            z
        );
        Self {
            idx: (x & CHUNK_MASK32) | ((y & CHUNK_MASK32) << CHUNK_MASK_SIZE) | ((z & CHUNK_MASK32) << (CHUNK_MASK_SIZE*2)),
        }
    }
    pub fn x(&self) -> u32 {
        self.idx & CHUNK_MASK32
    }
    pub fn y(&self) -> u32 {
        (self.idx >> CHUNK_MASK_SIZE) & CHUNK_MASK32
    }
    pub fn z(&self) -> u32 {
        (self.idx >> (CHUNK_MASK_SIZE*2)) & CHUNK_MASK32
    }
    pub fn uvec3(&self) -> UVec3 {
        UVec3::new(self.x() as u32, self.y() as u32, self.z() as u32)
    }
    pub fn ivec3(&self) -> IVec3 {
        IVec3::new(self.x() as i32, self.y() as i32, self.z() as i32)
    }
}

pub trait ToLocalPos {
    fn to_local_pos(&self) -> LocalPos;
}
impl ToLocalPos for IVec3 {
    #[track_caller]
    fn to_local_pos(&self) -> LocalPos {
        assert!(
            self.x >= 0 && self.x < CHUNK_SIZE32 as i32 && self.y >= 0 && self.y < CHUNK_SIZE32 as i32 && self.z >= 0 && self.z < CHUNK_SIZE32 as i32,
            "Local position out of bounds: {}, {}, {}",
            self.x,
            self.y,
            self.z
        );
        LocalPos::new(self.x.try_into().unwrap(), self.y.try_into().unwrap(), self.z.try_into().unwrap())
    }
}

impl ToLocalPos for UVec3 {
    #[track_caller]
    fn to_local_pos(&self) -> LocalPos {
        assert!(self.x < CHUNK_SIZE32  && self.y < CHUNK_SIZE32  && self.z < CHUNK_SIZE32,
            "Local position out of bounds: {}, {}, {}",
            self.x,
            self.y,
            self.z
        );
        LocalPos::new(self.x.try_into().unwrap(), self.y.try_into().unwrap(), self.z.try_into().unwrap())
    }
}
