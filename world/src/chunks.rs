use crate::*;

#[derive(ShaderType)]
// #[repr(C)]
#[derive(Default, Debug, Clone)]
pub struct VoxelChunk {
    // Todo: change idx_in_parent to u8 with 2 bits allocated to prefix_in_block_data_array ?
    pub idx_in_parent: u32,
    pub inner: [u32; ((CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE).div_ceil(32))],
    pub prefix_in_block_data_array: [u32; 4],
}
impl VoxelChunk {
    pub fn empty(idx_in_parent: u32, prefix_in_block_data_array: [u32; 4]) -> Self {
        Self {
            idx_in_parent,
            inner: [0; _],
            prefix_in_block_data_array,
        }
    }
    // pub const fn blocks(&self) -> u {
    //     self.inner.x as u64 | ((self.inner.y as u64) << 32)
    // }
    // pub const fn set_blocks(&mut self, blks: u64) {
    //     self.inner = uvec2((blks & u32::MAX as u64) as u32, (blks >> 32) as u32);
    // }
    pub const fn block_count(&self) -> u32 {
        let mut i = 0;
        let mut s = 0;
        while i < self.inner.len() {
            s += self.inner[i].count_ones() as u32;
            i += 1;
        }
        s
    }
    /// Returns values ranging between 0..4
    pub fn local_pos(&self) -> LocalPos {
        LocalPos {
            idx: self.idx_in_parent.try_into().unwrap(),
        }
    }
    /// Returns a value between 0..4
    // #[track_caller]
    // pub fn to_local_pos(&self, world_pos: IVec3, parent_pos: IVec3) -> LocalPos {

    //     LocalPos::new(out.x.try_into().unwrap(), out.y.try_into().unwrap(), out.z.try_into().unwrap())
    // }
    // pub fn to_local_pos(&self, world_pos: IVec3, parent_pos: IVec3) -> LocalPos {
    //     let out = (world_pos - (parent_pos * self.size as i32))
    //         .div_euclid(IVec3::splat(self.size as i32 / 4));

    //     LocalPos::new(out.x.try_into().unwrap(), out.y.try_into().unwrap(), out.z.try_into().unwrap())
    // }

    // pub const fn min(&self) -> IVec3 {self.pos}
    // pub fn max(&self) -> IVec3 {self.pos+IVec3::splat(self.size as i32)}
    // pub fn contains(&self, block_pos: IVec3) -> bool {
    //     !(block_pos.x < self.min().x || block_pos.y < self.min().y || block_pos.z < self.min().z) || (block_pos.x > self.max().x || block_pos.y > self.max().y || block_pos.z > self.max().z)
    // }
    pub const fn set_block(&mut self, local_pos: LocalPos) {
        let local_idx = local_pos.idx / 32;
        let local_bit = local_pos.idx % 32;
        self.inner[local_idx as usize] |= 1 << local_bit;
    }
    pub const fn get_block(&self, local_pos: LocalPos) -> bool {
        let local_idx = local_pos.idx / 32;
        let local_bit = local_pos.idx % 32;
        self.inner[local_idx as usize] & (1 << local_bit) != 0
    }

    pub const fn is_last(&self, local_pos: LocalPos) -> bool {
        debug_assert!(
            self.get_block(local_pos),
            "Checking is_last on a non-set block"
        );
        let local_idx = local_pos.idx / 32;
        let local_bit = local_pos.idx % 32;
        let next_mask = !((1 << local_bit) - 1);
        let next_bits_and_self = self.inner[local_idx as usize] & next_mask;
        if next_bits_and_self > 1 {
            return false;
        }
        let mut i = local_idx + 1;
        while i < self.inner.len() as u32 {
            // Check that all subsequent bits are 0
            if self.inner[i as usize] != 0 {
                return false;
            }
            i += 1;
        }
        true
    }
    pub const fn trailing_count(&self, local_pos: LocalPos) -> u32 {
        debug_assert!(
            self.get_block(local_pos),
            "Checking trailing on a non-set block"
        );
        let local_idx = local_pos.idx / 32;
        let local_bit = local_pos.idx % 32;
        let next_mask = !((1 << local_bit) - 1);
        let next_bits_and_self = self.inner[local_idx as usize] & next_mask;
        let mut i = local_idx + 1;
        let mut count = next_bits_and_self.count_ones() as u32 - 1;
        while i < self.inner.len() as u32 {
            // Check that all subsequent bits are 0
            if self.inner[i as usize] != 0 {
                count += self.inner[i as usize].count_ones() as u32;
            }
            i += 1;
        }
        count
    }

    // #[track_caller]
    // pub fn local_pos_to_map_data_idx(&self, local_pos: LocalPos) -> u32 {
    //     assert!(
    //         local_pos.idx < CHUNK_CUBE_SIZE32,
    //         "Index out of bounds: {}",
    //         local_pos.idx
    //     );
    //     let local_idx = local_pos.idx / 32;
    //     let local_bit = local_pos.idx % 32;
    //     let mut ones = 0;
    //     let mut i = 0;
    //     while i < local_idx {
    //         ones += self.inner[i as usize].count_ones() as u32;
    //         i += 1;
    //     }

    //     let curr_set_bits =
    //         (((1 << local_bit) - 1) & self.inner[local_idx as usize]).count_ones() as u32;
    //     //todo: make sure it works
    //     let chunk_idx = curr_set_bits + ones;
    //     let curr_array = size_to_array_array_idx(chunk_idx);
    //     let local_array_idx = chunk_idx - array_array_idx_to_prefix_size(curr_array) as u32;
    //     self.prefix_in_block_data_array[curr_array as usize] + local_array_idx
    // }

    /// Returns 0 if block count < 8
    /// 1 if block count < 16
    /// 2 if block count < 32
    /// 3 if block count < 64
    pub const fn array_array_idx(&self) -> u8 {
        let mut bc = self.block_count();
        if bc == 64 {bc=63}
        size_to_array_array_idx(bc)
    }
    pub fn local_pos_to_map_data_id(&self, local_pos: LocalPos) -> MapDataID {
        assert!(
            local_pos.idx < CHUNK_CUBE_SIZE32,
            "Index out of bounds: {}",
            local_pos.idx
        );
        let local_idx = local_pos.idx / 32;
        let local_bit = local_pos.idx % 32;
        let mut ones = 0;
        let mut i = 0;
        while i < local_idx {
            ones += self.inner[i as usize].count_ones() as u32;
            i += 1;
        }

        let curr_set_bits =
            (((1 << local_bit) - 1) & self.inner[local_idx as usize]).count_ones() as u32;
        //todo: make sure it works
        let chunk_idx = curr_set_bits + ones;
        assert!(chunk_idx < 64, "Chunk idx out of bounds: {} {self:?} {local_pos:?}", chunk_idx);
        let curr_array = size_to_array_array_idx(chunk_idx);
        let local_array_idx = chunk_idx - array_array_idx_to_prefix_size(curr_array) as u32;
        let array_idx = self.prefix_in_block_data_array[curr_array as usize] + local_array_idx;
        
        assert!(
            array_idx >= self.prefix_in_block_data_array[curr_array as usize]
            && (array_idx as u32) < (self.prefix_in_block_data_array[curr_array as usize]
                        + array_array_idx_to_size(self.array_array_idx()) as u32),
            "Invalid local position {:?} {} !> {}",
            local_pos,
            curr_array as usize,
            self.prefix_in_block_data_array[curr_array as usize]
        );
        MapDataID::new(
            array_idx,
            curr_array,
        )
    }
}
const SIZES: [usize; 4] = [
    array_array_idx_to_size(0),
    array_array_idx_to_size(1),
    array_array_idx_to_size(2),
    array_array_idx_to_size(3)
];
// ! MAKE SURE TO CHANGE SHADER CODE IN ACCORDANCE
pub const fn array_array_idx_to_size(array_array_idx: u8) -> usize {
    match array_array_idx {
        0 => 8, // Prefix: 0
        1 => 16, // Prefix: 8
        2 => 16, // Prefix: 24
        3 => 24, // Prefix: 40
        _ => unreachable!(),
    }
}
pub const fn size_to_array_array_idx(size: u32) -> u8 {
    const SIZES0: u32 = array_array_idx_to_prefix_size(1) as u32;
    const SIZES1: u32 = array_array_idx_to_prefix_size(2) as u32;
    const SIZES2: u32 = array_array_idx_to_prefix_size(3) as u32;
    match size {
        (0..SIZES0) => 0,
        (SIZES0..SIZES1) => 1,
        (SIZES1..SIZES2) => 2,
        (SIZES2..64) => 3,
        _ => unreachable!(),
    }
}
pub const fn array_array_idx_to_prefix_size(array_array_idx: u8) -> usize {
    
    match array_array_idx {
        0 => 0,
        1 => SIZES[0],
        2 => SIZES[0]+SIZES[1],
        3 => SIZES[0]+SIZES[1]+SIZES[2],
        _ => unreachable!(),
    }
}

pub fn depth_to_chunk_size(depth: u32) -> usize {
    CHUNK_SIZE.pow(depth)
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct MapDataID {
    pub array_idx: u32,
    pub array_array_idx: u8,
}
impl MapDataID {
    pub const fn new(array_idx: u32, array_array_idx: u8) -> Self {
        Self {
            array_array_idx,
            array_idx,
        }
    }
    pub const fn with_array_idx(&self, array_idx: u32) -> Self {
        Self {
            array_array_idx: self.array_array_idx,
            array_idx,
        }
    }
    pub const fn with_array_array_idx(&self, array_array_idx: u8) -> Self {
        Self {
            array_array_idx,
            array_idx: self.array_idx,
        }
    }
    pub const fn array_size(&self) -> usize {
        array_array_idx_to_size(self.array_array_idx)
    }
    pub const fn pack(&self) -> u32 {
        assert!(self.array_array_idx < 4);
        assert!(self.array_idx < (1 << 30));
        (self.array_array_idx) as u32 | (self.array_idx as u32) << 2
    }
    pub const fn unpack(packed: u32) -> Self {
        let array_array_idx = (packed & 0b11) as u8;
        let array_idx = (packed >> 2) as u32;
        Self::new(array_idx, array_array_idx)
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct VoxelChunkID {
    pub array_idx: u32,
}
impl VoxelChunkID {
    pub const fn new(array_idx: u32) -> Self {
        Self { array_idx }
    }
    pub const fn with_array_idx(&self, array_idx: u32) -> Self {
        Self { array_idx }
    }
}

pub const CHUNK_MASK: usize = CHUNK_SIZE - 1;
pub const CHUNK_MASK32: u32 = CHUNK_MASK as _;
pub const CHUNK_MASK_SIZE: u32 = CHUNK_MASK.count_ones();
pub const CHUNK_SIZE: usize = 4;
pub const CHUNK_SIZE32: u32 = CHUNK_SIZE as _;
pub const CHUNK_CUBE_SIZE32: u32 = ((CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE) as u32);
