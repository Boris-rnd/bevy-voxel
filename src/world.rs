use std::cell::UnsafeCell;

use bevy::{log, math::ops::rem_euclid, prelude::*, render::render_resource::ShaderType};

#[derive(ShaderType)]
#[repr(C)]
#[derive(Default, Debug)]
pub struct Sphere {
    pos: Vec3,
    rad: f32,
    color: Vec3,
}
pub fn sphere(pos: Vec3, rad: f32, color: Vec3) -> Sphere {
    Sphere { pos, rad, color }
}
#[derive(ShaderType)]
#[repr(C)]
#[derive(Default, Debug)]
pub struct Box {
    min: Vec3,
    max: Vec3,
    color: Vec3,
}
pub fn new_box(min: Vec3, max: Vec3, color: Vec3) -> Box {
    Box { min, max, color }
}
pub fn new_voxel(pos: Vec3) -> Box {
    new_box(
        pos - vec3(0.5, 0.5, 0.5),
        pos + vec3(0.5, 0.5, 0.5),
        vec3(1., 1., 1.),
    )
}

#[derive(ShaderType)]
#[repr(C)]
#[derive(Default, Debug)]
pub struct Voxel {
    pos: Vec3,
    texture_id: u32,
}

#[derive(ShaderType)]
#[repr(C)]
#[derive(Default, Debug)]
pub struct VoxelChunk {
    pub idx_in_parent: u32,
    pub inner: UVec2,
    pub prefix_in_block_data_array: u32,
}
impl VoxelChunk {
    pub const fn blocks(&self) -> u64 {
        self.inner.x as u64 | ((self.inner.y as u64) << 32)
    }
    pub const fn set_blocks(&mut self, blks: u64) {
        self.inner = uvec2((blks & u32::MAX as u64) as u32, (blks >> 32) as u32);
    }
    pub const fn block_count(&self) -> u32 {
        self.blocks().count_ones() as u32
    }
    /// Returns values ranging between 0..4
    pub fn local_pos(&self) -> LocalPos {
        LocalPos {
            idx: self.idx_in_parent as u8,
        }
    }
    /// Returns a value between 0..4
    // #[track_caller]
    // pub fn to_local_pos(&self, world_pos: IVec3, parent_pos: IVec3) -> LocalPos {

    //     LocalPos::new(out.x as u8, out.y as u8, out.z as u8)
    // }
    // pub fn to_local_pos(&self, world_pos: IVec3, parent_pos: IVec3) -> LocalPos {
    //     let out = (world_pos - (parent_pos * self.size as i32))
    //         .div_euclid(IVec3::splat(self.size as i32 / 4));

    //     LocalPos::new(out.x as u8, out.y as u8, out.z as u8)
    // }

    // pub const fn min(&self) -> IVec3 {self.pos}
    // pub fn max(&self) -> IVec3 {self.pos+IVec3::splat(self.size as i32)}
    // pub fn contains(&self, block_pos: IVec3) -> bool {
    //     !(block_pos.x < self.min().x || block_pos.y < self.min().y || block_pos.z < self.min().z) || (block_pos.x > self.max().x || block_pos.y > self.max().y || block_pos.z > self.max().z)
    // }
    pub const fn set_block(&mut self, local_pos: LocalPos) {
        self.set_blocks(self.blocks() | (1 << local_pos.idx));
    }
    pub const fn get_block(&self, local_pos: LocalPos) -> bool {
        (self.blocks() >> local_pos.idx) & 1 == 1
    }

    #[track_caller]
    fn local_pos_to_map_data_idx(&self, local_pos: LocalPos) -> u32 {
        assert!(local_pos.idx < 64, "Index out of bounds: {}", local_pos.idx);
        let blks = self.blocks();
        self.prefix_in_block_data_array + (((1 << local_pos.idx) - 1) & blks).count_ones() as u32
    }
}
pub fn voxel_chunk(
    idx_in_parent: u32,
    // size: u32,
    blks: u64,
    prefix_in_block_data_array: u32,
) -> VoxelChunk {
    VoxelChunk {
        idx_in_parent,
        // size,
        inner: uvec2((blks & u32::MAX as u64) as u32, (blks >> 32) as u32),
        prefix_in_block_data_array,
    }
}

pub struct ChunkMapData {
    /// If data&1<<2==0: chunk start
    /// else: smaller chunk definition
    data: u32,
}
impl ChunkMapData {
    pub fn chunk_start(chunk_id: u32) -> Self {
        Self {
            data: chunk_id << 3 | 0b001,
        }
    }
    pub fn inner_chunk(chunk_data_idx: u32) -> Self {
        // assert!(chunk_data.idx_in_parent<64);
        // assert!(chunk_data.inner.x<4);
        // assert!(chunk_data.inner.y<4);
        // assert!(chunk_data.size<8);
        // assert!(chunk_data.prefix_in_block_data_array<(1<<(32-14)));
        Self {
            data: (chunk_data_idx << 3) | 0b101,
            // data: (chunk_data.idx_in_parent & 0b111111 | (chunk_data.inner.x&0b11)<<6 | (chunk_data.inner.y&0b11)<<8 | (chunk_data.size&0b111)<<10 | (chunk_data.prefix_in_block_data_array&((1<<(32-13))-1))<<13)<<1 | 1,
        }
    }
    pub fn to_voxel_chunk_idx(&self) -> Option<u32> {
        if self.data & 1 << 3 == 0 {
            return None;
        }
        Some(self.data >> 3)
        // Some(voxel_chunk(idx_in_parent, size, blks, prefix_in_block_data_array))
    }
}

// #[derive(Default, Debug, PartialEq, Eq)]
// pub enum MapData {
//     #[default]
//     Padding,
//     Chunk,
//     Block,
//     // Points to next map informations in this chunk
//     Tail,
// }

#[derive(Default, PartialEq, Clone, Copy)]
pub enum MapData {
    #[default]
    Padding,
    Chunk(u32), // Chunk ID
    Block(u32), // Layer
    Tail(u32),  // Next index
}
impl MapData {
    pub fn is_padding(&self) -> bool {
        matches!(self, Self::Padding)
    }
    pub fn is_chunk(&self) -> bool {
        matches!(self, Self::Chunk(_))
    }
    pub fn is_block(&self) -> bool {
        matches!(self, Self::Block(_))
    }
    pub fn is_tail(&self) -> bool {
        matches!(self, Self::Tail(_))
    }
    pub fn pack(&self) -> MapDataPacked {
        match self {
            Self::Padding => MapDataPacked::default(),
            Self::Chunk(id) => {
                assert!(*id < (1 << 30), "Chunk ID too large: {}", id);
                MapDataPacked {
                    data: id << 2 | 0b01,
                }
            }
            Self::Block(layer) => {
                assert!(*layer < (1 << 30), "Layer too large: {}", layer);
                MapDataPacked {
                    data: layer << 2 | 0b10,
                }
            }
            Self::Tail(next_index) => {
                assert!(
                    *next_index < (1 << 30),
                    "Next index too large: {}",
                    next_index
                );
                MapDataPacked {
                    data: next_index << 2 | 0b11,
                }
            }
        }
    }
    pub fn get_next_index(&self) -> Option<u32> {
        // let a = crate::unpack!(self, Self::Tail(next_index));
        match self {
            Self::Tail(next_index) => Some(*next_index),
            _ => None,
        }
    }
    pub fn is_start_chunk(&self) -> bool {
        matches!(self, Self::Chunk(data) if data&0b100==0)
    }
    pub fn is_chunk_data(&self) -> bool {
        matches!(self, Self::Chunk(data) if data&0b100!=0)
    }
    pub fn chunk_data(&self) -> Option<u32> {
        if self.is_chunk_data() {
            match self {
                Self::Chunk(data) => Some(data >> 2),
                _ => unreachable!(),
            }
        } else {
            None
        }
    }
}

#[derive(ShaderType, Default, PartialEq, Clone, Copy)]
pub struct MapDataPacked {
    // 2 first bits = type:
    // 00=padding
    // 01=chunk
    // 10=block
    // 11=Tail
    pub data: u32,
}
impl MapDataPacked {
    pub fn unpack(&self) -> Option<MapData> {
        match self.data & 0b11 {
            0b00 => Some(MapData::Padding),
            0b01 => Some(MapData::Chunk(self.data >> 2)),
            0b10 => Some(MapData::Block(self.data >> 2)),
            0b11 => Some(MapData::Tail(self.data >> 2)),
            _ => unreachable!(),
        }
    }
}
impl std::fmt::Debug for MapDataPacked {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // self.unpack().map_or(
        //     writeln!(f, "Invalid MapDataPacked: {:b}", self.data),
        //     |data| writeln!(f, "{:?}", data),
        // )
        write!(f, "{:?}", self.unpack().unwrap())
    }
}

impl std::fmt::Debug for MapData {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MapData::Padding => write!(f, "Padding"),
            MapData::Chunk(id) => write!(f, "Chunk({})", id),
            MapData::Block(layer) => write!(f, "Block({})", layer),
            MapData::Tail(next_idx) => write!(f, "Tail({})", next_idx),
        }
    }
}

// #[macro_export]
// macro_rules! unpack {
//     ($enum: expr, $variant) => {
//         match $enum {
//             $variant => Some($variant),
//             _ => None,
//         }
//     };
// }

/// Represents a position in the local coordinate system of a chunk
/// Every coordinate is in the range [0, 3]
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq)]
pub struct LocalPos {
    // 6 bits used
    pub idx: u8,
}
impl LocalPos {
    #[track_caller]
    pub fn new(x: u8, y: u8, z: u8) -> Self {
        assert!(
            x < 4 && y < 4 && z < 4,
            "Local position out of bounds: {}, {}, {}",
            x,
            y,
            z
        );
        Self {
            idx: (x & 0b11) | ((y & 0b11) << 2) | ((z & 0b11) << 4),
        }
    }
    pub fn x(&self) -> u8 {
        self.idx & 0b11
    }
    pub fn y(&self) -> u8 {
        (self.idx >> 2) & 0b11
    }
    pub fn z(&self) -> u8 {
        (self.idx >> 4) & 0b11
    }
    pub fn uvec3(&self) -> UVec3 {
        UVec3::new(self.x() as u32, self.y() as u32, self.z() as u32)
    }
    pub fn ivec3(&self) -> IVec3 {
        IVec3::new(self.x() as i32, self.y() as i32, self.z() as i32)
    }
}

#[derive(Default, Debug)]
pub struct GameWorld {
    pub spheres: Vec<Sphere>,
    pub boxes: Vec<Box>,
    pub voxels: Vec<Voxel>,
    // pub root_chunk: VoxelChunk,
    pub voxel_chunks: Vec<VoxelChunk>,
    pub block_data: Vec<MapDataPacked>,
}
impl GameWorld {
    pub fn set_map_data(&mut self, idx: usize, data: MapData) {
        self.block_data[idx] = data.pack();
    }
    pub fn set_data_in_chunk(&mut self, chunk_id: usize, local_pos: LocalPos, data: MapData) {
        let chunk = &mut self.voxel_chunks[chunk_id];

        // If block is already set, simply replace the data
        if chunk.get_block(local_pos) {
            let map_data_idx = chunk.local_pos_to_map_data_idx(local_pos) as usize;
            self.set_map_data(map_data_idx, data);
            return;
        }
        chunk.set_block(local_pos);
        let map_data_idx = chunk.local_pos_to_map_data_idx(local_pos) as usize;

        // Insert the data and update subsequent chunks' prefixes
        self.block_data.insert(map_data_idx, data.pack());
        for other_chunk in self.voxel_chunks.iter_mut().skip(chunk_id + 1) {
            other_chunk.prefix_in_block_data_array += 1;
        }
    }

    pub fn get_data_in_chunk(&self, chunk_id: usize, local_pos: LocalPos) -> Option<MapData> {
        let chunk = &self.voxel_chunks[chunk_id];

        // If block isn't set, return None
        if !chunk.get_block(local_pos) {
            return None;
        }

        // Count set bits before our position to find data index
        let map_data_idx = chunk.local_pos_to_map_data_idx(local_pos) as usize;
        if map_data_idx >= self.block_data.len() {
            return None;
        }
        self.get_map_data(map_data_idx)
    }
    pub fn root_chunk(&self) -> &VoxelChunk {
        &self.voxel_chunks[0]
    }
    pub fn root_size(&self) -> usize {
        4u32.pow(4) as _
    }
    fn block_iter_inner(&mut self, pos: IVec3, map_data: Option<MapData>) -> Option<MapData> {
        if pos.x < self.root_size() as i32
            || pos.y < self.root_size() as i32
            || pos.z < self.root_size() as i32
        {
            let mut curr_idx = 0;
            let mut parent_pos = IVec3::ZERO;
            let mut local_pos = pos;
            if map_data.is_none() {
                log::trace!("\n------Getting block at {:?}-------", pos);
            } else {
                log::trace!(
                    "\n------Setting block at {:?} with data {:?}-------",
                    pos,
                    map_data
                );
            }
            for depth in 1..100 {
                let chunk = &self.voxel_chunks[curr_idx];
                let chunk_size = self.root_size() as i32 / (4i32.pow(depth - 1));
                parent_pos += chunk.local_pos().ivec3() * chunk_size;
                local_pos = (pos - parent_pos).div_euclid(IVec3::splat(chunk_size / 4));
                log::trace!("{depth}: {local_pos:?} -> Chunk {curr_idx} (offset: {parent_pos:?}) with size: {}", chunk_size);
                if chunk_size == 4 && map_data.is_some() {
                    // If the chunk is 4x4x4, we can set the block directly
                    log::trace!("Setting block in chunk {curr_idx} at local pos {local_pos:?}");
                    self.set_data_in_chunk(curr_idx, local_pos.to_local_pos(), map_data.unwrap());
                    return None;
                }

                // If the chunk is smaller, we need to go deeper
                match self.get_data_in_chunk(curr_idx, local_pos.to_local_pos()) {
                    Some(data) => match data {
                        MapData::Chunk(id) => {
                            log::trace!("Got smaller chunk {id} with parent pos {parent_pos:?}");
                            curr_idx = id as usize;
                        }
                        MapData::Block(layer) => match map_data {
                            Some(data) => {
                                log::trace!(
                                    "Block data already exists at {:?}, replacing with {:?}",
                                    local_pos,
                                    map_data
                                );
                                self.set_data_in_chunk(curr_idx, local_pos.to_local_pos(), data);
                            }
                            None => return Some(data),
                        },
                        _ => {
                            panic!("Unexpected map data type: {:?}", data);
                        }
                    },
                    None => {
                        // If there is no data in the root chunk, we need to create a new chunk
                        match map_data {
                            Some(data) => {
                                // Setting block
                                log::trace!("Chunk {curr_idx} at {local_pos:?}={} is empty, filling with new chunk {} at offset {} in block data array", local_pos.to_local_pos().idx, self.voxel_chunks.len(), self.block_data.len());
                                let v = voxel_chunk(
                                    local_pos.to_local_pos().idx as u32,
                                    0,
                                    self.block_data.len() as u32,
                                );
                                let prev_idx = curr_idx;
                                curr_idx = self.voxel_chunks.len(); // Because we are going to push a new chunk, idx will be the last index
                                self.voxel_chunks.push(v);
                                self.set_data_in_chunk(
                                    prev_idx,
                                    local_pos.to_local_pos(),
                                    MapData::Chunk(curr_idx as u32),
                                );
                            } // Get block
                            None => {
                                log::trace!("No data found in chunk {curr_idx} at local pos {local_pos:?}, returning None");
                                log::trace!(
                                    "{local_pos}={} in {:b}",
                                    local_pos.to_local_pos().idx,
                                    self.voxel_chunks[curr_idx].blocks()
                                );
                                if self.voxel_chunks[curr_idx].get_block(local_pos.to_local_pos()) {
                                    log::trace!("But bit is set !");
                                }
                                return None;
                            }
                        }
                    }
                }
            }
            panic!("Maximum iterations reached, something is wrong with the chunk data structure");
        } else {
            todo!()
        }
    }

    pub fn set_block(&mut self, pos: IVec3, map_data: MapData) {
        assert!(matches!(map_data, MapData::Block(_)));
        self.block_iter_inner(pos, Some(map_data));
    }

    pub fn get_block(&self, pos: IVec3) -> Option<MapData> {
        #[allow(invalid_reference_casting)]
        unsafe { UnsafeCell::from_mut(&mut *(self as *const GameWorld as *mut GameWorld)) }
            .get_mut()
            .block_iter_inner(pos, None)
    }

    pub fn pretty_print(&self) -> String {
        let mut out = String::new();
        use std::fmt::Write;
        writeln!(&mut out, "GameWorld:").unwrap();
        let mut blks = self.root_chunk().blocks();
        while blks != 0 {
            let idx = blks.trailing_zeros();
            let local_pos = LocalPos::new(
                (idx & 0b11) as u8,
                ((idx >> 2) & 0b11) as u8,
                ((idx >> 4) & 0b11) as u8,
            );
            let map_data_idx = self.root_chunk().local_pos_to_map_data_idx(local_pos);
            let map_data = self
                .get_map_data(map_data_idx as usize)
                .unwrap_or(MapData::Padding);
            let val = match map_data {
                MapData::Chunk(c) => format!(
                    "block count: {} local pos: {:?} prefix_idx: {}",
                    self.voxel_chunks[c as usize].blocks().count_ones(),
                    self.voxel_chunks[c as usize].local_pos().ivec3(),
                    self.voxel_chunks[c as usize].prefix_in_block_data_array
                ),
                _ => todo!(),
            };
            writeln!(
                &mut out,
                "{:?}: {:?} with {val}",
                local_pos.ivec3(),
                map_data
            )
            .unwrap();
            blks &= !(1 << idx);
        }
        out
    }

    // pub fn get_chunk_id_from_block_pos(&self, pos: IVec3) -> Option<usize> {
    //     let cp = Self::to_chunk_pos(pos);
    //     for (i, chunk) in self.voxel_chunks.iter().enumerate() {
    //         if chunk.pos == cp {
    //             return Some(i);
    //         }
    //     }
    //     None
    // }
    pub fn to_chunk_pos(pos: IVec3, chunk_size: u32) -> IVec3 {
        pos.div_euclid(IVec3::splat(chunk_size as i32))
    }
    pub fn block_pos_to_delta_pos(pos: IVec3, chunk_size: u32) -> IVec3 {
        pos.rem_euclid(IVec3::splat(chunk_size as i32))
    }
    /// Takes an index in map data and returns it if it's not a tail
    /// if idx not in bounds, will return idx !
    fn map_data_follow_tails(&self, idx: usize) -> usize {
        let data = self.get_map_data(idx).unwrap_or(MapData::Padding);
        match data {
            MapData::Tail(next_idx) => self.map_data_follow_tails(next_idx as usize),
            _ => idx,
        }
    }
    fn get_map_data(&self, idx: usize) -> Option<MapData> {
        self.block_data.get(idx).and_then(|data| data.unpack())
    }

    // fn get_map_data_mut(&mut self, idx: usize) -> Option<&mut MapData> {
    //     self.block_data.get_mut(self.map_data_follow_tails(idx))
    // }
}

fn local_chunk_pos_to_idx(pos: IVec3) -> u32 {
    assert!((pos.x < 4 && pos.y < 4 && pos.z < 4));
    assert!((pos.x >= 0 && pos.y >= 0 && pos.z >= 0));
    (pos.x + pos.y * 4 + pos.z * 16) as u32
}

pub trait ToLocalPos {
    fn to_local_pos(&self) -> LocalPos;
}
impl ToLocalPos for IVec3 {
    #[track_caller]
    fn to_local_pos(&self) -> LocalPos {
        assert!(
            self.x >= 0 && self.x < 4 && self.y >= 0 && self.y < 4 && self.z >= 0 && self.z < 4,
            "Local position out of bounds: {}, {}, {}",
            self.x,
            self.y,
            self.z
        );
        LocalPos::new(self.x as u8, self.y as u8, self.z as u8)
    }
}
