use bevy::{math::ops::rem_euclid, prelude::*, render::render_resource::ShaderType};

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
    new_box(pos-vec3(0.5, 0.5, 0.5), pos+vec3(0.5, 0.5, 0.5), vec3(1., 1., 1.))
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
    pub size: u32,
    pub inner: UVec2,
    pub prefix_in_block_data_array: u32,
}
impl VoxelChunk {
    pub const fn blocks(&self) -> u64 {
        self.inner.x as u64 | ((self.inner.y as u64)<<32)
    }
    pub const fn set_blocks(&mut self, blks: u64) {
        self.inner = uvec2((blks&u32::MAX as u64) as u32, (blks>>32) as u32);
    }
    pub const fn block_count(&self) -> u32 {
        self.blocks().count_ones() as u32
    }
    /// Returns values ranging between 0..4
    pub fn local_pos(&self) -> IVec3 {
        IVec3::new(self.idx_in_parent as i32 % 4, (self.idx_in_parent as i32 / 4) % 4, self.idx_in_parent as i32 / 16)
    }
    /// Returns a value between 0..4
    #[track_caller]
    pub fn to_local_pos(&self, world_pos: IVec3, parent_pos: IVec3) -> IVec3 {
        let out = (world_pos - (parent_pos*self.size as i32)).div_euclid(IVec3::splat(self.size as i32/4));
        assert!(out.x < 4 && out.y < 4 && out.z < 4, "Local position out of bounds: {:?} {world_pos:?} {parent_pos:?}", out);
        assert!(out.x >= 0 && out.y >= 0 && out.z >= 0, "Local position negative: {:?} {world_pos:?} {parent_pos:?}", out);
        out
    }
    // pub const fn min(&self) -> IVec3 {self.pos}
    // pub fn max(&self) -> IVec3 {self.pos+IVec3::splat(self.size as i32)}
    // pub fn contains(&self, block_pos: IVec3) -> bool {
    //     !(block_pos.x < self.min().x || block_pos.y < self.min().y || block_pos.z < self.min().z) || (block_pos.x > self.max().x || block_pos.y > self.max().y || block_pos.z > self.max().z)
    // }
    #[track_caller]
    pub const fn local_pos_to_idx(&self, local_pos: IVec3) -> u32 {
        assert!(local_pos.x < 4 && local_pos.y < 4 && local_pos.z < 4);
        assert!(local_pos.x >= 0 && local_pos.y >= 0 && local_pos.z >= 0);
        (local_pos.x + local_pos.y * 4 + local_pos.z * 16) as u32
    }
    pub const fn set_block(&mut self, idx: u32) {
        self.set_blocks(self.blocks() | (1 << idx));
    }
    pub const fn get_block(&mut self, idx: u32) -> bool {
        self.blocks() & (1 << idx) == 1
    }
    pub const fn set_block_at(&mut self, local_pos: IVec3) {
        self.set_block(self.local_pos_to_idx(local_pos))
    }
    pub const fn get_block_at(&mut self, local_pos: IVec3) -> bool {
        self.get_block(self.local_pos_to_idx(local_pos))
    }
    
    #[track_caller]
    fn local_idx_to_map_data_idx(&self, idx: u32) -> u32 {
        assert!(idx < 64, "Index out of bounds: {}", idx);
        let blks = self.blocks();
        self.prefix_in_block_data_array + (((1<<idx)-1) & blks).count_ones() as u32
    }
}
pub fn voxel_chunk(idx_in_parent: u32, size: u32, blks: u64, prefix_in_block_data_array: u32) -> VoxelChunk {
    VoxelChunk { idx_in_parent, size, inner: uvec2((blks&u32::MAX as u64) as u32, (blks>>32) as u32), prefix_in_block_data_array }
}

pub struct ChunkMapData {
    /// If data&1<<2==0: chunk start
    /// else: smaller chunk definition
    data: u32
}
impl ChunkMapData {
    pub fn chunk_start(chunk_id: u32, ) -> Self {
        Self {
            data: chunk_id<<3 | 0b001
        }
    }
    pub fn inner_chunk(chunk_data_idx: u32) -> Self {
        // assert!(chunk_data.idx_in_parent<64);
        // assert!(chunk_data.inner.x<4);
        // assert!(chunk_data.inner.y<4);
        // assert!(chunk_data.size<8);
        // assert!(chunk_data.prefix_in_block_data_array<(1<<(32-14)));
        Self {
            data: (chunk_data_idx<<3) | 0b101,
            // data: (chunk_data.idx_in_parent & 0b111111 | (chunk_data.inner.x&0b11)<<6 | (chunk_data.inner.y&0b11)<<8 | (chunk_data.size&0b111)<<10 | (chunk_data.prefix_in_block_data_array&((1<<(32-13))-1))<<13)<<1 | 1,
        }
    }
    pub fn to_voxel_chunk_idx(&self) -> Option<u32> {
        if self.data&1<<3==0 {return None;}
        Some(self.data>>3)
        // Some(voxel_chunk(idx_in_parent, size, blks, prefix_in_block_data_array))
    }
}

#[derive(Default, Debug, PartialEq, Eq)]
pub enum MapType {
    #[default]
    Padding,
    Chunk,
    Block,
    // Points to next map informations in this chunk
    Tail,
}

#[derive(ShaderType)]
#[derive(Default)]
pub struct MapData {
    // 2 first bits = type:
    // 00=padding
    // 01=chunk
    // 10=block
    // 11=Tail
    pub layer: u32,
}
impl MapData {
    pub fn ty(&self) -> Option<MapType> {
        match self.layer&0b11 {
            0b00 => Some(MapType::Padding),
            0b01 => Some(MapType::Chunk),
            0b10 => Some(MapType::Block),
            0b11 => Some(MapType::Tail),
            _ => unreachable!(),
        }
    }

    pub fn block(layer: u32) -> Self {
        Self {
            layer: layer<<2 | 0b10,
        }
    }
    pub fn chunk(data: ChunkMapData) -> Self {
        Self {
            layer: data.data,
        }
    }
    pub fn padding() -> Self {
        Self::default()
    }
    pub fn tail(next_index: u32) -> Self {
        Self {
            // Set type bits to 11 and store next_index in remaining bits
            layer: (0b11 | (next_index << 2)),
        }
    }

    pub fn get_next_index(&self) -> Option<u32> {
        if self.ty() == Some(MapType::Tail) {
            assert!(self.layer >> 2 != 0);
            Some(self.layer >> 2)
        } else {
            None
        }
    }
    pub fn is_start_chunk(&self) -> bool {
        self.ty()==Some(MapType::Chunk) && self.layer&0b100==0
    }
    pub fn is_chunk_data(&self) -> bool {
        self.ty()==Some(MapType::Chunk) && self.layer&0b100!=0
    }
    pub fn chunk_data(&self) -> Option<u32> {
        if self.is_chunk_data() {
            Some(self.layer >> 3)
        } else {
            None
        }
    }
}

impl std::fmt::Debug for MapData {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.ty() {
            Some(MapType::Padding) => write!(f, "Padding"),
            Some(MapType::Chunk) => write!(f, "Chunk({})", self.chunk_data().unwrap_or(0)),
            Some(MapType::Block) => write!(f, "Block({})", self.layer >> 2),
            Some(MapType::Tail) => write!(f, "Tail({})", self.get_next_index().unwrap_or(0)),
            None => write!(f, "Unknown"),
        }
    }
}

#[derive(Default, Debug)]
pub struct GameWorld {
    pub spheres: Vec<Sphere>,
    pub boxes: Vec<Box>,
    pub voxels: Vec<Voxel>,
    // pub root_chunk: VoxelChunk,
    pub voxel_chunks: Vec<VoxelChunk>,
    pub block_data: Vec<MapData>,
}
impl GameWorld {
    pub fn set_data_in_chunk(&mut self, chunk_id: usize, local_pos: IVec3, data: MapData) {
        let idx = local_chunk_pos_to_idx(local_pos);
        assert!(idx < 64, "Index out of bounds: {}", idx);
        let mut map_data_idx = self.voxel_chunks[chunk_id].local_idx_to_map_data_idx(idx) as usize;
        map_data_idx = self.map_data_follow_tails(map_data_idx);
        let chunk = &mut self.voxel_chunks[chunk_id];
        if chunk.get_block(idx) {
            dbg!(local_pos, idx, chunk.blocks());
            dbg!(chunk.prefix_in_block_data_array);
            dbg!(&self.block_data[map_data_idx]);
            // Replace
            self.block_data[map_data_idx] = data;
        } else {
            chunk.set_block(idx);
            if idx > chunk.block_count() { // Append
                if map_data_idx >= self.block_data.len() {
                    println!("Map data index out of bounds: {} >= {}", map_data_idx, self.block_data.len());
                    self.block_data.push(data);
                } else {
                    // Move other chunk
                    self.block_data.insert(map_data_idx, data);
                }
            } else { // Insert
                self.block_data.insert(map_data_idx, data);
            }
            // match self.block_data[map_data_idx].ty() {
            //     Some(MapType::Padding) => {
            //         // If the data is padding, we need to replace it with the new data
            //         self.block_data[map_data_idx] = data;
            //     },
            //     _ => {
            //         panic!("Unexpected map data type: {:?}", self.block_data[map_data_idx].ty());
            //     }
            // }
        }
    }
    pub fn get_data_in_chunk(&mut self, chunk_id: usize, local_pos: IVec3) -> Option<&MapData> {
        let idx = local_chunk_pos_to_idx(local_pos);
        assert!(idx < 64, "Index out of bounds: {}", idx);
        let mut map_data_idx = self.voxel_chunks[chunk_id].local_idx_to_map_data_idx(idx) as usize;
        map_data_idx = self.map_data_follow_tails(map_data_idx);
        let chunk = &mut self.voxel_chunks[chunk_id];
        println!("Getting data {map_data_idx} -> {:?} {}", self.block_data.get(map_data_idx), chunk.get_block(idx));
        if chunk.get_block(idx) {
            // dbg!(local_pos, idx, chunk.blocks());
            // dbg!(chunk.prefix_in_block_data_array);
            // dbg!(&self.block_data[map_data_idx]);
            // Replace
            Some(&self.block_data[map_data_idx])
        } else {
            None
        }
    }
    pub fn root_chunk(&mut self) -> &mut VoxelChunk {
        &mut self.voxel_chunks[0]
    }
    pub fn set_block(&mut self, pos: IVec3, map_data: MapData) {
        if pos.x < self.root_chunk().size as i32 || pos.y < self.root_chunk().size as i32 || pos.z < self.root_chunk().size as i32 {
            assert_eq!(map_data.ty(), Some(MapType::Block));
            let mut curr_idx = 0;
            let mut map_data_idx = 0;
            let mut parent_pos = IVec3::ZERO;
            println!("\nSetting block at {:?} with data {:?}\n", pos, map_data);
            for i in 0..100 {
                print!("{i}: {pos:?} -> ");
                let mut local_pos = self.voxel_chunks[curr_idx].to_local_pos(pos, parent_pos);
                println!("{local_pos:?} in chunk {curr_idx} at parent pos {parent_pos:?}");
                match self.get_data_in_chunk(curr_idx, local_pos) {
                    Some(data) => {
                        println!("Chunk data at {data:?}");
                        match data.ty() {
                            Some(MapType::Chunk) => {
                                curr_idx = data.chunk_data().unwrap() as usize;
                                if self.voxel_chunks[curr_idx].size == 4 {
                                    // If the chunk is 4x4x4, we can set the block directly
                                    self.set_data_in_chunk(curr_idx, local_pos, map_data);
                                    return;
                                } else {
                                    // If the chunk is smaller, we need to go deeper
                                    parent_pos = self.voxel_chunks[curr_idx].local_pos();
                                }
                            },
                            Some(MapType::Block) => {
                                todo!("Block data already exists at {:?}, cannot overwrite with {:?}", local_pos, map_data);
                                self.set_data_in_chunk(curr_idx, local_pos, map_data);
                                return;
                            },
                            _ => {
                                panic!("Unexpected map data type: {:?}", data.ty());
                            }
                        }
                    },
                    None => {
                        // If there is no data in the root chunk, we need to create a new chunk
                        let size = self.voxel_chunks[curr_idx].size;
                        if size == 4 {
                            // If the chunk is 4x4x4, we can set the block directly
                            self.set_data_in_chunk(curr_idx, local_pos, map_data);
                            return;
                        }
                        let v = voxel_chunk(local_chunk_pos_to_idx(local_pos), size/4, 0, self.block_data.len() as u32);
                        print!("No data, creating new chunk: {v:?}");
                        self.voxel_chunks.push(v);
                        curr_idx = self.voxel_chunks.len()-1;
                        parent_pos = self.voxel_chunks[curr_idx].local_pos();
                        println!(" at {curr_idx}");
                        self.set_data_in_chunk(curr_idx, local_pos, MapData::chunk(ChunkMapData::inner_chunk(curr_idx as u32)));
                    },
                }
            }
            panic!("Maximum iterations reached, something is wrong with the chunk data structure");
        } else {todo!()}
        //     while curr.size != 4 {
        //         local_pos = curr.to_local_pos(parent_pos);
        //         dbg!(local_pos, pos);
        //         let idx = local_chunk_pos_to_idx(local_pos);
        //         assert!(idx < 64, "Index out of bounds: {}", idx);
        //         map_data_idx = curr.local_idx_to_map_data_idx(idx) as usize;
        //         map_data_idx = self.map_data_follow_tails(map_data_idx);
        //         // If the chunk is not 4x4x4, we need to create a new chunk
        //         // with smaller size
        //         let blks = 1<<idx;
        //         let new_chunk = voxel_chunk(idx, curr.size/4, blks, self.block_data.len() as u32);
        //         self.voxel_chunks.push(new_chunk);
                
        //     }
        //     curr.set_block(local_pos);

        //     if map_data_idx>=self.block_data.len()+1 {
        //         todo!("Nothing at {}, {}", map_data_idx, self.block_data.len());
        //     } else if map_data_idx==self.block_data.len() {
        //         self.block_data.push(map_data);
        //     } else {
        //         let end_idx = self.map_data_follow_tails(map_data_idx as _);
        //         let data = &self.block_data[end_idx];
        //         println!("Overwritting data at {:?} with {:?}", pos, map_data);
        //         self.block_data[end_idx] = map_data;
        //     }
        //     // self.set_block_in_root(pos, map_data);
        // } else {
        //     todo!();
        //     // Make new root 4x bigger to englobe previous root chunk
        //     // self.voxel_chunks.push(self.root_chunk());
        //     // let prev_pos = self.root_chunk().pos;
        //     // self.root_chunk() = voxel_chunk(prev_pos, self.root_chunk().size*4, 0, self.block_data.len() as _);
        //     // self.root_chunk().set_block(pos - self.root_chunk().min());

        // } 
        // let cp = Self::to_chunk_pos(pos);
        // let delta_pos = Self::block_pos_to_delta_pos(pos);
        
        // match self.get_chunk_id_from_block_pos(pos) {
        //     Some(id) => {
        //         let idx = Self::delta_pos_to_idx(delta_pos);
        //         let chunk = &mut self.voxel_chunks[id];
        //         let was_set = chunk.blocks() & (1 << idx) != 0;
                
        //         if !was_set {
        //             // Add new block at end of array
        //             let new_idx = self.block_data.len() as u32;
        //             self.block_data.push(map_data);

        //             // Count set bits before our position (excluding the current bit)
        //             let count = (chunk.blocks() & ((1 << idx) - 1)).count_ones();
                    
        //             if count == 0 {
        //                 // First block in sequence - update chunk's prefix and point to old chain
        //                 let old_prefix = chunk.prefix_in_block_data_array;
        //                 chunk.prefix_in_block_data_array = new_idx;
        //                 if old_prefix != 0 {
        //                     self.block_data.push(MapData::tail(old_prefix));
        //                 }
        //             } else {
        //                 // Follow the chain until we find the insertion point
        //                 let mut current_idx = chunk.prefix_in_block_data_array;
        //                 let mut found_count = 0;
                        
        //                 // Keep track of previous block to detect end of chain
        //                 let mut prev_idx = current_idx;
                        
        //                 while found_count < count {
        //                     match self.block_data[current_idx as usize].get_next_index() {
        //                         Some(next) => {
        //                             prev_idx = current_idx;
        //                             current_idx = next;
        //                             found_count += 1;
        //                         }
        //                         None => {
        //                             // We've reached the end of the chain
        //                             self.block_data[prev_idx as usize] = MapData::tail(new_idx);
        //                             break;
        //                         }
        //                     }
        //                 }
                        
        //                 // If we found the right position in the middle of the chain
        //                 if found_count == count {
        //                     let next = self.block_data[prev_idx as usize].get_next_index();
        //                     self.block_data[prev_idx as usize] = MapData::tail(new_idx);
        //                     if let Some(next) = next {
        //                         self.block_data.push(MapData::tail(next));
        //                     }
        //                 }
        //             }
                    
        //             // Update the chunk's block mask after everything else is set up
        //             chunk.set_blocks(chunk.blocks() | (1 << idx));
        //         }
        //     },
        //     None => {
        //         println!("Generating chunk {:?} from block pos: {:?}", cp, pos);
        //         let idx = Self::delta_pos_to_idx(delta_pos);
        //         let voxels = 1<<idx;
        //         let prefix_in_block_data_array = self.block_data.len();
        //         self.block_data.push(map_data);
        //         let chunk = voxel_chunk(cp, voxels, prefix_in_block_data_array as _);
        //         self.voxel_chunks.push(chunk);
        //     },
    }
    // pub fn get_block(&self, pos: IVec3) -> Option<&MapData> {
    //     let cp = Self::to_chunk_pos(pos);
    //     if let Some(id) = self.get_chunk_id_from_block_pos(pos) {
    //         let delta_pos = Self::block_pos_to_delta_pos(pos);
    //         let idx = Self::delta_pos_to_idx(delta_pos);
    //         let chunk = &self.voxel_chunks[id];
    //         let blks = chunk.blocks();
    //         if blks & (1 << idx) != 0 {
    //             let target_count = (blks & ((1 << idx) - 1)).count_ones();
                
    //             // Follow linked list
    //             let mut current_idx = chunk.prefix_in_block_data_array;
    //             let mut found_count = 0;
    //             while found_count < target_count {
    //                 if let Some(next) = self.block_data[current_idx as usize].get_next_index() {
    //                     current_idx = next;
    //                     found_count += 1;
    //                 } else {
    //                     return None; // Corrupted list
    //                 }
    //             }
    //             return Some(&self.block_data[current_idx as usize]);
    //         }
    //     }
    //     None
    // }

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
        let binding = MapData::padding();
        let data = &self.block_data.get(idx).unwrap_or(&binding);
        if data.ty() == Some(MapType::Tail) {
            self.map_data_follow_tails(data.get_next_index().unwrap() as usize)
        } else {idx}
    }
    fn get_map_data(&self, idx: usize) -> Option<&MapData> {
        // if idx as usize > self.block_data.len() {return None}
        self.block_data.get(self.map_data_follow_tails(idx))
    }
    

    // fn get_map_data_mut(&mut self, idx: usize) -> Option<&mut MapData> {
    //     self.block_data.get_mut(self.map_data_follow_tails(idx))
    // }
}

fn local_chunk_pos_to_idx(pos: IVec3) -> u32 {
    assert!((pos.x<4 && pos.y<4 && pos.z<4));
    assert!((pos.x>=0 && pos.y>=0 && pos.z>=0));
    (pos.x+pos.y*4+pos.z*16) as u32
}
