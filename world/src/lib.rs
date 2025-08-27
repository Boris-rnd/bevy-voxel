#![feature(generic_const_exprs)]
#![feature(vec_push_within_capacity)]
#![allow(unused, dead_code)]
#![allow(incomplete_features)]
// Temporary code to allow static mutable references
#![allow(static_mut_refs)]
#![allow(ambiguous_glob_reexports)]
use std::{cell::OnceCell, ops::RangeInclusive};

pub use bevy::prelude::*;
use bevy::render::{extract_resource::ExtractResourcePlugin, render_asset::RenderAssets, storage::GpuShaderStorageBuffer};
pub use bevy::{
    asset::RenderAssetUsages,
    color::palettes::css::WHITE,
    pbr::{NotShadowCaster, NotShadowReceiver},
    prelude::*,
    render::{
        batching::NoAutomaticBatching,
        render_resource::AsBindGroup,
        render_resource::{Extent3d, TextureDimension, TextureFormat, TextureUsages, ShaderType, ShaderRef},
        storage::ShaderStorageBuffer,
        view::NoFrustumCulling,
        
    },
    sprite::{AlphaMode2d, Material2d, Material2dPlugin},
};
pub use noise::{NoiseFn, Perlin};

use std::{cell::UnsafeCell, time::Instant};

use bevy::{log, math::ops::rem_euclid, prelude::*};
use noise::NoiseFn as _;


pub mod chunks;
pub mod shapes;
pub mod map_data;
pub mod common;
pub use chunks::*;
pub use shapes::*;
pub use map_data::*;
pub use common::*;

pub fn unpack_all(data: &[MapDataPacked]) -> Vec<MapData> {
    data.iter().map(|d| d.unpack().unwrap()).collect()
}


#[derive(Default, Debug, Resource, Clone)]
pub struct GameWorld {
    // pub spheres: Vec<Sphere>,
    // pub boxes: Vec<Box>,
    // pub voxels: Vec<Voxel>,
    // pub root_chunk: VoxelChunk,
    // Stores arrays of arrays, which depends on block count on chunk
    pub voxel_chunks: Vec<VoxelChunk>,
    pub block_data: [Vec<MapDataPacked>; 4],
    pub root_max_depth: u32,
    pub realloc_count: usize,
    pub realloc_count_chunks: usize,
    pub pad_count: usize,
}
impl GameWorld {
    pub fn new(world_size: u64, pad_count: u32) -> Self {
        let root_max_depth = world_size.ilog(CHUNK_SIZE as _);
        let mut voxel_chunks = Vec::with_capacity(WORLD_SIZE_TO_LEN.get((root_max_depth as usize)-4).unwrap_or(&WORLD_SIZE_TO_LEN_DEFAULT).0);
        let mut block_data = Vec::with_capacity(WORLD_SIZE_TO_LEN.get((root_max_depth as usize)-4).unwrap_or(&WORLD_SIZE_TO_LEN_DEFAULT).1);
        for _ in 0..array_array_idx_to_size(0) {
            block_data.push(MapData::Padding.pack());
        }
        // Push a root chunk
        voxel_chunks.push(VoxelChunk::empty(0, [0; 4]));
        Self {
            block_data: [block_data, vec![], vec![], vec![]],
            voxel_chunks,
            root_max_depth,
            pad_count: pad_count as usize,
            ..Default::default()
        }
    }
    #[track_caller]
    pub fn set_map_data(&mut self, map_data_id: MapDataID, value: MapData) {
        for i in 0..4 {
            assert!(self.block_data[i].len() % MapDataID::new(0, i as _).array_size() as usize==0);
        }
        assert!(self.block_data[map_data_id.array_array_idx as usize].len() >= map_data_id.array_idx as usize, "{map_data_id:?} {value:?}");
        self.block_data[map_data_id.array_array_idx as usize][map_data_id.array_idx as usize] = value.pack();
    }
    #[track_caller]
    pub fn get_map_data(&self, map_data_id: MapDataID) -> Option<MapData> {
        self.block_data[map_data_id.array_array_idx as usize].get(map_data_id.array_idx as usize).map(|data| data.unpack().unwrap())
    }
    #[track_caller]
    pub fn push_map_data(&mut self, map_data_id: MapDataID, value: MapData) {
        self.block_data[map_data_id.array_array_idx as usize].push_within_capacity(value.pack()).unwrap();
    }
    #[track_caller]
    pub fn push_map_data_padding_with_array_id(&mut self, id: MapDataID) {
        assert!(id.array_idx % (id.array_size() as u32) != 0, "id isn't aligned properly");
        self.block_data[id.array_array_idx as usize].append(&mut vec![MapData::Padding.pack(); id.array_size() as usize]);
    }
    #[track_caller]
    pub fn get_map_data_with_array_id(&self, id: MapDataID) -> &[MapDataPacked] {
        assert!(id.array_idx as usize + id.array_size() as usize <= self.block_data[id.array_array_idx as usize].len(), "id is out of bounds");
        assert!(id.array_idx % id.array_size() as usize as u32 != 0, "id isn't aligned properly");
        &self.block_data[id.array_array_idx as usize][id.array_idx as usize..id.array_idx as usize + id.array_size() as usize]
    }
    #[track_caller]
    pub fn set_map_data_with_array_id(&mut self, id: MapDataID, data: &[MapDataPacked]) {
        assert!(id.array_idx as usize + id.array_size() as usize <= self.block_data[id.array_array_idx as usize].len(), "id is out of bounds");
        assert!(id.array_idx % id.array_size() as u32 == 0, "id isn't aligned properly");
        self.block_data[id.array_array_idx as usize][id.array_idx as usize..id.array_idx as usize + id.array_size() as usize].iter_mut().zip(data.iter()).for_each(|(slot, data)| *slot = *data);
    }
    #[track_caller]
    pub fn get_voxel_chunk(&self, voxel_chunk_id: VoxelChunkID) -> Option<&VoxelChunk> {
        self.voxel_chunks.get(voxel_chunk_id.array_idx as usize)
    }
    #[track_caller]
    pub fn get_voxel_chunk_mut(&mut self, voxel_chunk_id: VoxelChunkID) -> Option<&mut VoxelChunk> {
        self.voxel_chunks.get_mut(voxel_chunk_id.array_idx as usize)
    }
    // pub fn get_chunk_data(&self, chunk_id: VoxelChunkID) -> Option<&[MapDataPacked]> {
    //     self.block_data[chunk_id.array_array_idx as usize].get(chunk_id.array_idx as usize..)
    // }

    pub fn set_data_in_chunk(&mut self, chunk_id: VoxelChunkID, local_pos: LocalPos, data: MapData) {
        // Shenanigans to overcome the borrow checker
        let chunk = self.get_voxel_chunk(chunk_id).unwrap();
        let prev_array_array_idx = chunk.array_array_idx();
        // If block is already set, simply replace the data
        if chunk.get_block(local_pos) {
            let map_data_idx = chunk.local_pos_to_map_data_id(local_pos);
            self.set_map_data(map_data_idx, data);
            return;
        }
        
        // Has to use mut, so new reference and chunk is reset so borrow checker is happy
        self.get_voxel_chunk_mut(chunk_id).unwrap().set_block(local_pos);
        let chunk = self.get_voxel_chunk(chunk_id).unwrap(); // Get it back for borrow checker

        let new_array_array_idx = chunk.array_array_idx(); // get updated array_array_idx, which may have changed because we added a block
        if new_array_array_idx != prev_array_array_idx { // Chunk is now too big, has to go to bigger map_data array
            let mut new_data = Vec::with_capacity(array_array_idx_to_size(new_array_array_idx));
            for i in 0..(new_data.capacity() - new_data.len()) { // Fill the vec up with padding to follow alignment
                new_data.push(MapData::Padding.pack());
            }
            let new_data_len = new_data.len(); // Store len because .append makes new_data empty and we need it after (order matters)
            self.block_data[new_array_array_idx as usize].append(&mut new_data);
            self.get_voxel_chunk_mut(chunk_id).unwrap().prefix_in_block_data_array[new_array_array_idx as usize] = (self.block_data[new_array_array_idx as usize].len() - new_data_len) as u32;
            // log::trace!("New data length: {} at {}", new_data_len, new_array_array_idx);
        }
        let chunk = self.get_voxel_chunk(chunk_id).unwrap(); // Get it back for borrow checker
        // Now we have to move all other elements from the chunk that are more to the right in the array
        let new_map_data_idx = chunk.local_pos_to_map_data_id(local_pos);
        let end_array_array_idx = new_array_array_idx;
        // Copy prefixes to be used in the loop without getting chunk from memory every time
        let prefixes = chunk.prefix_in_block_data_array;
        let end_array_idxs = [
            prefixes[0]+array_array_idx_to_size(0) as u32,
            prefixes[1]+array_array_idx_to_size(1) as u32,
            prefixes[2]+array_array_idx_to_size(2) as u32,
            prefixes[3]+array_array_idx_to_size(3) as u32,
        ];
        let mut overflow_ele = data.pack();
        for array_array_idx in new_map_data_idx.array_array_idx..=end_array_array_idx {
            let start = if array_array_idx==new_map_data_idx.array_array_idx { new_map_data_idx.array_idx } else { prefixes[array_array_idx as usize] };
            let end = end_array_idxs[array_array_idx as usize];
            if start==end { // Nothing to move
                continue;
            }
            // dbg!(new_map_data_idx, array_array_idx, start,end, overflow_ele, data, self.get_voxel_chunk(chunk_id).unwrap());
            let sub_data = self.block_data[array_array_idx as usize][start as usize..end as usize].to_vec();
            // Move sub_data by one to the right, but needs to take into account the end of the allocated slice per chunk, so if something overflows, have to move to the bigger array_array_idx
            self.block_data[array_array_idx as usize][start as usize] = overflow_ele;
            overflow_ele = *sub_data.last().unwrap();
            self.block_data[array_array_idx as usize][start as usize + 1..end as usize].copy_from_slice(&sub_data[..sub_data.len()-1]);
            if overflow_ele == MapData::Padding.pack() {
                break;
            }
        }

        // self.set_map_data(new_map_data_idx, data);

        // return;
        

        //TODO If need to reallocate chunk, also check if previous count is low, above threshold, just replace the whole chunk
        
        // if map_data_idx.array_idx as usize >= self.block_data[map_data_idx.array_idx as usize].len() {
        //     // If idx is out of bounds, we need to reallocate
        //     self.block_data[map_data_idx.array_idx as usize].push_within_capacity(data.pack()).unwrap();
        //     // for i in 0..self.pad_count { // Can potentially add less padding, if chunk is nearly full
        //     //     self.block_data.push_within_capacity(MapData::Padding.pack()).unwrap();
        //     // }
        // } else if self.block_data[map_data_idx.array_idx as usize][map_data_idx.array_array_idx as usize] == MapData::Padding.pack() { // Is last & padding, can simply replace
        //     self.block_data[map_data_idx.array_idx as usize][map_data_idx.array_array_idx as usize] = data.pack();
        // } else if trailing_count == 0 { // Is last should never happen, because it would point to another chunk's data, but we should always have trailing padding
        //     dbg!(map_data_idx, &self.get_map_data(map_data_idx), &self.get_voxel_chunk(chunk_id), local_pos, data);
        //     todo!();
        // } else { // Trailing count>0 so we need to shift subsequent data
        //     //TODO Check if we have enough space, if so, shift in place, else reallocate at end of array
        //     // For this, we accumulate all subsequent data, and reallocate them at end of array
        //     let mut subsequent_data = Vec::with_capacity(trailing_count as usize);
        //     for i in 0..trailing_count {
        //         // Get the block_data at map_data_idx+1+i, following tails, and replace it with padding
        //         let idx = self.map_data_follow_tails(map_data_idx+1+i as usize);
        //         let sub_data = std::mem::replace(&mut self.block_data[idx], MapData::Padding.pack());
        //         // let sub_data = *self.block_data.get(self.map_data_follow_tails(map_data_idx+1+i as usize)).expect("Chunk thinks data exist but not in block_data array, so data array is corrupted");
        //         subsequent_data.push(sub_data);
        //     }
        //     // Now we have all subsequent data, we can reallocate them at end of array
        //     self.block_data[map_data_idx] = MapData::Tail(self.block_data.len() as _).pack();
        //     self.block_data.append(&mut subsequent_data);
        // }

        // let curr = self.get_map_data_follow_tails(map_data_idx);


        // // Insert the data and update subsequent chunks' prefixes
        // if self.block_data.get(map_data_idx).unwrap_or(&MapData::Block(0).pack()) != &MapData::Padding.pack() { // This shouldn't happen
        //     todo!();
        //     self.block_data.insert(map_data_idx, data.pack());
        //     self.realloc_count += 1;
        //     for other_chunk in self.voxel_chunks.iter_mut().skip(chunk_id + 1) {
        //         other_chunk.prefix_in_block_data_array += 1;
        //         self.realloc_count_chunks += 1;
        //     }
        // } else {
        //     if self.block_data.get(map_data_idx+1).unwrap() != &MapData::Padding.pack() { // Check if next is padding, if not, we need to set itself to a tail and allocate new space
        //         self.block_data[map_data_idx] = MapData::Tail(self.block_data.len() as _).pack();
        //         log::trace!("Inserting tail at idx {}, realloc_count: {}", self.block_data.len(), self.realloc_count);
        //         self.realloc_count += 1;

        //         self.block_data.push_within_capacity(data.pack()).unwrap();
        //         // Allocate some new space for the actual data
        //         for i in 0..(self.pad_count) { // Can potentially add less padding, if chunk is nearly full
        //             self.block_data.push_within_capacity(MapData::Padding.pack()).unwrap();
        //         }
        //     } else { // Simple replace
        //         self.block_data[map_data_idx] = data.pack();
        //     }
        // }
    }

    pub fn get_data_in_chunk(&self, chunk_id: VoxelChunkID, local_pos: LocalPos) -> Option<MapData> {
        let chunk = self.get_voxel_chunk(chunk_id).unwrap();

        // If block isn't set, return None
        if !chunk.get_block(local_pos) {
            return None;
        }

        // Count set bits before our position to find data index
        self.get_map_data(chunk.local_pos_to_map_data_id(local_pos))
    }
    pub fn root_chunk(&self) -> &VoxelChunk {
        self.get_voxel_chunk(VoxelChunkID::new(0)).unwrap()
    }
    pub fn root_size(&self) -> usize {
        CHUNK_SIZE.pow(self.root_max_depth())
    }
    pub fn root_max_depth(&self) -> u32 {
        self.root_max_depth
    }
    /// Returns the allocated chunks position
    fn alloc_new_chunk(&mut self, idx_in_parent: LocalPos, parent_chunk_id: VoxelChunkID) -> VoxelChunkID {
        log::trace!("Chunk {parent_chunk_id:?} at {idx_in_parent:?}={} is empty, filling with new chunk {} at offset {} in block data array", idx_in_parent.idx, self.voxel_chunks.len(), self.block_data[0].len());
        let v = VoxelChunk::empty(
            idx_in_parent.idx,
            [self.block_data[0].len() as u32, 0, 0, 0],
        );
        self.voxel_chunks.push(v);
        let new_id = VoxelChunkID::new((self.voxel_chunks.len()-1) as _);
        self.block_data[0].extend_from_slice(&[MapData::Padding.pack(); array_array_idx_to_size(0)]);
        self.set_data_in_chunk(
            parent_chunk_id,
            idx_in_parent,
            MapData::Chunk(new_id.array_idx),
        );
        // Make space for new chunk's data
        new_id
    }

    fn block_iter_inner(&mut self, pos: IVec3, map_data: Option<MapData>) -> Option<MapData> {
        if pos.x < self.root_size() as i32
            || pos.y < self.root_size() as i32
            || pos.z < self.root_size() as i32
        {
            let mut map_data_id = VoxelChunkID::new(0);
            let mut parent_pos = IVec3::ZERO;
            let mut local_pos;
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
                let chunk = self.get_voxel_chunk(map_data_id).unwrap();
                let chunk_size = self.root_size() as u32 / (depth_to_chunk_size(depth - 1) as u32);
                parent_pos += chunk.local_pos().ivec3() * chunk_size as i32;
                local_pos = ((pos - parent_pos).div_euclid(IVec3::splat((chunk_size / CHUNK_SIZE32) as _)));
                log::trace!("{depth}: {local_pos:?} -> Chunk {map_data_id:?} (offset: {parent_pos:?}) with size: {}", chunk_size);
                if chunk_size == CHUNK_SIZE32 && map_data.is_some() {
                    // If the chunk is 4x4x4, we can set the block directly
                    log::trace!("Setting block in chunk {map_data_id:?} at local pos {local_pos:?}");
                    self.set_data_in_chunk(map_data_id, local_pos.to_local_pos(), map_data.unwrap());
                    return None;
                }

                // If the chunk is smaller, we need to go deeper
                match self.get_data_in_chunk(map_data_id, local_pos.to_local_pos()) {
                    Some(data) => match data {
                        MapData::Chunk(id) => {
                            let id = VoxelChunkID::new(id);
                            log::trace!("Got smaller chunk {id:?} with parent pos {parent_pos:?}");
                            map_data_id = id;
                        }
                        MapData::Block(layer) => match map_data {
                            Some(data) => {
                                log::trace!(
                                    "Block data already exists at {:?}, replacing with {:?}",
                                    local_pos,
                                    map_data
                                );
                                self.set_data_in_chunk(map_data_id, local_pos.to_local_pos(), data);
                            }
                            None => return Some(data),
                        },
                        _ => {
                            dbg!(pos, map_data, parent_pos, local_pos, map_data_id, depth, chunk);
                            dbg!(&self.block_data);
                            panic!("Unexpected map data type: {:?}", data);
                        }
                    },
                    None => {
                        // If there is no data in the root chunk, we need to create a new chunk
                        match map_data {
                            Some(data) => {// Setting block
                                map_data_id = self.alloc_new_chunk(local_pos.to_local_pos(), map_data_id);
                            } // Get block
                            None => {
                                log::trace!("No data found in chunk {map_data_id:?} at local pos {local_pos:?}, returning None");
                                log::trace!(
                                    "{local_pos}={} in {:b}",
                                    local_pos.to_local_pos().idx,
                                    chunk.block_count()
                                );
                                if chunk.get_block(local_pos.to_local_pos()) {
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
            dbg!(pos, self.root_size(), map_data);
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
        todo!()
        // let mut out = String::new();
        // use std::fmt::Write;
        // writeln!(&mut out, "GameWorld:").unwrap();
        // let mut blks = self.root_chunk().blocks();
        // while blks != 0 {
        //     let idx = blks.trailing_zeros();
        //     let local_pos = LocalPos {idx};
        //     let map_data_idx = self.root_chunk().local_pos_to_map_data_idx(local_pos);
        //     let map_data = self
        //         .get_map_data(map_data_idx as usize)
        //         .unwrap_or(MapData::Padding);
        //     let val = match map_data {
        //         MapData::Chunk(c) => format!(
        //             "block count: {} local pos: {:?} prefix_idx: {}",
        //             self.voxel_chunks[c as usize].blocks().count_ones(),
        //             self.voxel_chunks[c as usize].local_pos().ivec3(),
        //             self.voxel_chunks[c as usize].prefix_in_block_data_array
        //         ),
        //         _ => todo!(),
        //     };
        //     writeln!(
        //         &mut out,
        //         "{:?}: {:?} with {val}",
        //         local_pos.ivec3(),
        //         map_data
        //     )
        //     .unwrap();
        //     blks &= !(1 << idx);
        // }
        // out
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
    // / Takes an index in map data and returns it if it's not a tail
    // / if idx not in bounds, will return idx !
    // fn map_data_follow_tails(&self, idx: usize) -> usize {
    //     let data = self.get_map_data(idx).unwrap_or(MapData::Padding);
    //     match data {
    //         MapData::Tail(next_idx) => self.map_data_follow_tails(next_idx as usize),
    //         _ => idx,
    //     }
    // }
    // fn get_map_data(&self, idx: usize) -> Option<MapData> {
    //     self.block_data.get(idx).and_then(|data| data.unpack())
    // }
    // fn get_map_data_follow_tails(&self, idx: usize) -> Option<MapData> {
    //     self.block_data.get(self.map_data_follow_tails(idx)).and_then(|data| data.unpack())
    // }

    // fn get_map_data_mut(&mut self, idx: usize) -> Option<&mut MapData> {
    //     self.block_data.get_mut(self.map_data_follow_tails(idx))
    // }
}

pub const WORLD_SIZE_TO_LEN: &[(usize, usize)] = &[
    (10000, 100_000), // 4
    (100781, 3_007_062), // 5
];
pub const WORLD_SIZE_TO_LEN_DEFAULT: (usize, usize) = WORLD_SIZE_TO_LEN[0];

pub fn gen_world_size(size: u64) -> GameWorld {
    let mut world = GameWorld::new(size, 8);
    let perlin = noise::Perlin::new(1);
    for x in 0..world.root_size() as i32 {
        if x%16==0 {
            print!("Done {}/{}\r", x, world.root_size());
            std::io::Write::flush(&mut std::io::stdout()).unwrap();
        }
        for y in 1..3 {
            for z in 0..world.root_size() as i32 {
                // if perlin.get([x as f64, y as f64, z as f64])>0.0 {
                world.set_block(
                    ivec3(
                        x,
                        ((perlin.get([x as f64 / 50., z as f64 / 50.]) * 10.) as i32 + y).abs(),
                        z,
                    ),
                    MapData::Block(((x + y + z) % 15) as u32),
                );
            }
        }
    }
    world
}


pub fn gen_world() -> GameWorld {
    let mut start = Instant::now();
    let world = gen_world_size(4096);

    println!("Realloc count: {} \t Realloc count chunks: {}\n Mem usage: {} MB", &world.realloc_count, &world.realloc_count_chunks, world.block_data.len()*std::mem::size_of::<MapData>()/1024/1024);
    println!("Took {:?} to run", start.elapsed());
    println!("-----\n");
    world
}
// Tests ran with 1024 world size:
// world.voxel_chunks.len() = 94781
// &world.block_data.len() = 2191932

//                  (realloc_count, realloc_count_chunks)
//  W/O padding:        2191932         407609304           => 1.56s
//  1 padding:          2097152         407604936           => 1.56s
// 

// PAD_COUNT: 0
// Realloc count: 2191932   Realloc count chunks: 407609304
//  Mem usage: 16 MB
// Took 1.570278597s to run
// -----

// PAD_COUNT: 1
// Realloc count: 2097152   Realloc count chunks: 407604936
//  Mem usage: 16 MB
// Took 1.594867896s to run
// -----

// PAD_COUNT: 2
// Realloc count: 2005559   Realloc count chunks: 406822996
//  Mem usage: 16 MB
// Took 1.664875791s to run
// -----

// PAD_COUNT: 3
// Realloc count: 1917103   Realloc count chunks: 405276796
//  Mem usage: 16 MB
// Took 1.644745186s to run
// -----

// PAD_COUNT: 4
// Realloc count: 1831926   Realloc count chunks: 402987054
//  Mem usage: 16 MB
// Took 1.63590592s to run
// -----

// PAD_COUNT: 5
// Realloc count: 1753162   Realloc count chunks: 389050398
//  Mem usage: 16 MB
// Took 1.586025639s to run
// -----

// PAD_COUNT: 6
// Realloc count: 1683848   Realloc count chunks: 373672002
//  Mem usage: 17 MB
// Took 1.573984052s to run
// -----

// PAD_COUNT: 7
// Realloc count: 1624164   Realloc count chunks: 357962744
//  Mem usage: 17 MB
// Took 1.515006882s to run
// -----

// PAD_COUNT: 8
// Realloc count: 1592434   Realloc count chunks: 349848881
//  Mem usage: 17 MB
// Took 1.511781956s to run
// -----

// PAD_COUNT: 9
// Realloc count: 1585777   Realloc count chunks: 348137424
//  Mem usage: 18 MB
// Took 1.538062247s to run
// -----

// PAD_COUNT: 10
// Realloc count: 1585713   Realloc count chunks: 348116653
//  Mem usage: 19 MB
// Took 1.597236614s to run
// -----

// PAD_COUNT: 11
// Realloc count: 1585713   Realloc count chunks: 348116653
//  Mem usage: 20 MB
// Took 1.607988483s to run
// -----

// PAD_COUNT: 12
// Realloc count: 1585713   Realloc count chunks: 348116653
//  Mem usage: 20 MB
// Took 1.722870191s to run
// -----

// PAD_COUNT: 13
// Realloc count: 1585713   Realloc count chunks: 348116653
//  Mem usage: 21 MB
// Took 1.775363607s to run
// -----

// PAD_COUNT: 14
// Realloc count: 1585713   Realloc count chunks: 348116653
//  Mem usage: 22 MB
// Took 1.771380371s to run
// -----

// PAD_COUNT: 15
// Realloc count: 1585713   Realloc count chunks: 348116653
//  Mem usage: 22 MB
// Took 1.76268187s to run
// -----