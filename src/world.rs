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

#[derive(Default, Debug)]
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
    pub fn tail(layer: u32) -> Self {
todo!()
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
                chunk.set_blocks(chunk.blocks() | (1<<idx));
                let count = (chunk.blocks() & ((1 << idx) - 1)).count_ones();
                let arr_idx = (chunk.prefix_in_block_data_array+count) as usize;
                if arr_idx>=self.block_data.len() {
                    let dt = arr_idx-self.block_data.len();
                    for _ in 0..=dt {self.block_data.push(MapData::default());}
                }
                self.block_data[arr_idx] = map_data;
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
            if blks & (1<<idx) != 0 {
                let count = (blks & ((1 << idx) - 1)).count_ones();
                // dbg!(count, idx);
                return Some(&self.block_data[(chunk.prefix_in_block_data_array+count) as usize]);
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
