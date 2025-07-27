use bevy::{prelude::*, render::render_resource::ShaderType};

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
    pub pos: IVec3,
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
}
pub fn voxel_chunk(pos: IVec3, blks: u64, prefix_in_block_data_array: u32) -> VoxelChunk {
    VoxelChunk { pos, inner: uvec2((blks&u32::MAX as u64) as u32, (blks>>32) as u32), prefix_in_block_data_array }
}

#[derive(Default, Debug, PartialEq, Eq)]
pub enum MapType {
    #[default]
    Block,
    Chunk,
    Entity,
    // Points to next map informations in this chunk
    Tail,
}

#[derive(ShaderType)]
#[derive(Default, Debug)]
pub struct MapData {
    // 2 first bits = type:
    // 00=block
    // 01=chunk
    // 10=entity
    // 11=Tail
    pub layer: u32,
}
impl MapData {
    pub fn ty(&self) -> Option<MapType> {
        match self.layer&0b11 {
            0b00 => Some(MapType::Block),
            0b01 => Some(MapType::Chunk),
            0b10 => Some(MapType::Entity),
            0b11 => Some(MapType::Tail),
            _ => unreachable!(),
        }
    }

    pub fn block(layer: u32) -> Self {
        Self {
            layer: layer<<2,
        }
    }
    pub fn chunk(layer: u32) -> Self {
todo!()
    }
    pub fn entity(layer: u32) -> Self {
todo!()
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
}

#[derive(Default, Debug)]
pub struct GameWorld {
    pub spheres: Vec<Sphere>,
    pub boxes: Vec<Box>,
    pub voxels: Vec<Voxel>,
    pub voxel_chunks: Vec<VoxelChunk>,
    pub block_data: Vec<MapData>,
}
impl GameWorld {
    pub fn set_block(&mut self, pos: IVec3, map_data: MapData) {
        let cp = Self::to_chunk_pos(pos);
        let delta_pos = Self::block_pos_to_delta_pos(pos);
        // dbg!(pos, cp, delta_pos);
        match self.get_chunk_id_from_block_pos(pos) {
            Some(id) => {
                let idx = Self::delta_pos_to_idx(delta_pos);
                let chunk = &mut self.voxel_chunks[id];
                let was_set = chunk.blocks() & (1 << idx) != 0;
                
                if !was_set {
                    // Add new block at end of array
                    let new_idx = self.block_data.len() as u32;
                    self.block_data.push(map_data);

                    // Count set bits before our position (excluding the current bit)
                    let count = (chunk.blocks() & ((1 << idx) - 1)).count_ones();
                    
                    if count == 0 {
                        // First block in sequence - update chunk's prefix and point to old chain
                        let old_prefix = chunk.prefix_in_block_data_array;
                        chunk.prefix_in_block_data_array = new_idx;
                        if old_prefix != 0 {
                            self.block_data.push(MapData::tail(old_prefix));
                        }
                    } else {
                        // Follow the chain until we find the insertion point
                        let mut current_idx = chunk.prefix_in_block_data_array;
                        let mut found_count = 0;
                        
                        // Keep track of previous block to detect end of chain
                        let mut prev_idx = current_idx;
                        
                        while found_count < count {
                            match self.block_data[current_idx as usize].get_next_index() {
                                Some(next) => {
                                    prev_idx = current_idx;
                                    current_idx = next;
                                    found_count += 1;
                                }
                                None => {
                                    // We've reached the end of the chain
                                    self.block_data[prev_idx as usize] = MapData::tail(new_idx);
                                    break;
                                }
                            }
                        }
                        
                        // If we found the right position in the middle of the chain
                        if found_count == count {
                            let next = self.block_data[prev_idx as usize].get_next_index();
                            self.block_data[prev_idx as usize] = MapData::tail(new_idx);
                            if let Some(next) = next {
                                self.block_data.push(MapData::tail(next));
                            }
                        }
                    }
                    
                    // Update the chunk's block mask after everything else is set up
                    chunk.set_blocks(chunk.blocks() | (1 << idx));
                }
            },
            None => {
                println!("Generating chunk {:?} from block pos: {:?}", cp, pos);
                let idx = Self::delta_pos_to_idx(delta_pos);
                let voxels = 1<<idx;
                let prefix_in_block_data_array = self.block_data.len();
                self.block_data.push(map_data);
                let chunk = voxel_chunk(cp, voxels, prefix_in_block_data_array as _);
                self.voxel_chunks.push(chunk);
            },
        }
    }
    pub fn get_block(&self, pos: IVec3) -> Option<&MapData> {
        let cp = Self::to_chunk_pos(pos);
        if let Some(id) = self.get_chunk_id_from_block_pos(pos) {
            let delta_pos = Self::block_pos_to_delta_pos(pos);
            let idx = Self::delta_pos_to_idx(delta_pos);
            let chunk = &self.voxel_chunks[id];
            let blks = chunk.blocks();
            if blks & (1 << idx) != 0 {
                let target_count = (blks & ((1 << idx) - 1)).count_ones();
                
                // Follow linked list
                let mut current_idx = chunk.prefix_in_block_data_array;
                let mut found_count = 0;
                while found_count < target_count {
                    if let Some(next) = self.block_data[current_idx as usize].get_next_index() {
                        current_idx = next;
                        found_count += 1;
                    } else {
                        return None; // Corrupted list
                    }
                }
                return Some(&self.block_data[current_idx as usize]);
            }
        }
        None
    }

    pub fn get_chunk_id_from_block_pos(&self, pos: IVec3) -> Option<usize> {
        let cp = Self::to_chunk_pos(pos);
        for (i, chunk) in self.voxel_chunks.iter().enumerate() {
            if chunk.pos == cp {
                return Some(i);
            }
        }
        None
    }
    pub fn to_chunk_pos(pos: IVec3) -> IVec3 {
        pos.div_euclid(IVec3::splat(4))
    }
    pub fn block_pos_to_delta_pos(pos: IVec3) -> IVec3 {
        pos.rem_euclid(IVec3::splat(4))
    }
    // Returns idx between 0-64
    pub fn delta_pos_to_idx(pos: IVec3) -> usize {
        assert!((pos.x<4 && pos.y<4 && pos.z<4));
        assert!((pos.x>=0 && pos.y>=0 && pos.z>=0));
        (pos.x+pos.y*4+pos.z*16) as _
    }
}
