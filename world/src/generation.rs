use crate::*;
use bevy::{platform::collections::HashMap, prelude::*};

pub fn gen_world_size(size: u64) -> GameWorld {
    let mut world = GameWorld::new(size, 8);
    let perlin = noise::Perlin::new(1);
    // let mut out = bevy::platform::collections::HashMap::new();
    // out.insert(VoxelChunkID::new(0), (VoxelChunk::empty(0,[0;4]), vec![]));
    let max_depth = world.root_max_depth();
    for cx in (0..world.root_size() as i32).step_by(4) {
        if cx % 16 == 0 {
            print!("Done {}/{}\r", cx, world.root_size());
            std::io::Write::flush(&mut std::io::stdout()).unwrap();
        }
        for cy in (0..16).step_by(4) {
            for cz in (0..world.root_size() as i32).step_by(4) {
                // gen_parent_chunks(cx, cz, &mut out);
                let chunk_coords = ivec3(cx, cy, cz);
                world.set_block(chunk_coords, MapData::Block(0));
                let parent_chunk = world.get_block_depth(chunk_coords, world.root_max_depth()-1).unwrap();
                match parent_chunk {
                    MapData::Chunk(id) => {
                        let (new_blks, datas) = gen_chunk(chunk_coords, &perlin, &mut world);
                        let mut parent_chunk = &mut world.voxel_chunks[id as usize];
                        for (local_pos, data) in datas {
                            world.set_data_in_chunk(VoxelChunkID::new(id), local_pos, data.unpack().unwrap());
                        }
                        world.voxel_chunks[id as usize].inner = new_blks;
                    }
                    _ => {panic!("Unexpected parent chunk type {:?}", parent_chunk)}
                }
            }
        }
    }
    world
}

// fn gen_parent_chunks(cx: i32, cz: i32, out: &mut HashMap<VoxelChunkID, (VoxelChunk, Vec<MapDataPacked>)>) {
//     let chunk_coords = ivec3(cx, 1, cz);
//     let (root, root_vals) = &mut out.get(&VoxelChunkID::new(0)).unwrap();
//     if root.get_block(local_pos)
// }

fn gen_chunk(
    origin: IVec3,
    perlin: &noise::Perlin,
    world: &mut GameWorld,
) -> ([u32; CHUNK_U32_LEN], Vec<(LocalPos, MapDataPacked)>) {
    let mut blks_mask = [0u32; CHUNK_U32_LEN];
    let mut map_data = Vec::with_capacity(64);
    for x in 0..4 {
        for z in 0..4 {
            let world_pos = ivec3(origin.x + x, origin.y, origin.z + z);
            let height = ((perlin.get([world_pos.x as f64 / 50., world_pos.z as f64 / 50.]) * 15.)
                as i32)
                .abs();
            if world_pos.y > height {
                continue;
            }
            if height > world_pos.y && height < world_pos.y + 4 {
                let data = MapData::Block(0);
                write_small_chunk(
                    &mut blks_mask,
                    &mut map_data,
                    ivec3(x, height-world_pos.y, z).to_local_pos(),
                    data,
                );
            }
            for i in 0..(height.min(3)) {
                let data = if (i + world_pos.y) == height - 1 {
                    MapData::Block(2)
                } else {
                    MapData::Block(1)
                };
                write_small_chunk(
                    &mut blks_mask,
                    &mut map_data,
                    ivec3(x, i, z).to_local_pos(),
                    data,
                );
            }
        }
    }
    (blks_mask, map_data)
}
fn write_small_chunk(
    blks_mask: &mut [u32; CHUNK_U32_LEN],
    map_data: &mut Vec<(LocalPos, MapDataPacked)>,
    local_pos: LocalPos,
    data: MapData,
) {
    blks_mask[(local_pos.idx / 32) as usize] |= 1 << (local_pos.idx % 32);
    map_data.push((local_pos, data.pack()));
}

pub fn gen_world() -> GameWorld {
    let mut start = Instant::now();
    let world = gen_world_size(1024);

    println!(
        "Realloc count: {} \t Realloc count chunks: {}\n Mem usage: {} MB",
        &world.realloc_count,
        &world.realloc_count_chunks,
        world.block_data.len() * std::mem::size_of::<MapData>() / 1024 / 1024
    );
    println!("Took {:?} to run", start.elapsed());
    println!("-----\n");
    world
}