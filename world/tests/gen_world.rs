#[test]
pub fn gen_world_test_paddings() {
    for i in 0..10 {
        println!("PAD_COUNT: {i}");
        let mut start = Instant::now();
        let world_size = 1024u32;
        let root_max_depth = world_size.ilog(CHUNK_SIZE as _);
        let mut voxel_chunks = Vec::with_capacity(WORLD_SIZE_TO_LEN.get((root_max_depth as usize)-4).unwrap_or(&WORLD_SIZE_TO_LEN_DEFAULT).0);
        voxel_chunks.push(VoxelChunk::empty(0, 0));
    
        let mut world = GameWorld {
            block_data: Vec::with_capacity(WORLD_SIZE_TO_LEN.get((root_max_depth as usize)-4).unwrap_or(&WORLD_SIZE_TO_LEN_DEFAULT).1),
            voxel_chunks,
            root_max_depth,
            pad_count: i,
            ..Default::default()
        };
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
        
    for x in 0..world.root_size() as i32 {
        if x%16==0 {
            print!("Done {}/{}\r", x, world.root_size());
            std::io::Write::flush(&mut std::io::stdout()).unwrap();
        }
        for y in 1..3 {
            for z in 0..world.root_size() as i32 {
                // if perlin.get([x as f64, y as f64, z as f64])>0.0 {
                assert_eq!(world.get_block(
                    ivec3(
                        x,
                        ((perlin.get([x as f64 / 50., z as f64 / 50.]) * 10.) as i32 + y).abs(),
                        z,
                    )),
                    Some(MapData::Block(((x + y + z) % 15) as u32)),
                );
            }
        }
    }
    
        // println!("World size: {:?}", world.root_size());
        // dbg!(&world.voxel_chunks.len());
        // dbg!(&world.block_data.len());
        println!("Realloc count: {} \t Realloc count chunks: {}\n Mem usage: {} MB", &world.realloc_count, &world.realloc_count_chunks, world.block_data.len()*std::mem::size_of::<MapData>()/1024/1024);
        println!("Took {:?} to run", start.elapsed());
        println!("-----\n");
    }
}

use std::time::Instant;

use noise::NoiseFn as _;

pub use world::*;

#[test]
fn gen_random() {
    let perlin = noise::Perlin::new(1);
    let mut placed = bevy::platform::collections::HashMap::new();
    let mut world = GameWorld::default();
    for i in 0..1_000 {
        let coords = ivec3(
            (rand::random::<f32>() * 100.) as i32,
            (rand::random::<f32>() * 20.) as i32,
            (rand::random::<f32>() * 100.) as i32,
        );
        let blk = MapData::Block(rand::random::<u32>() % 15);
        world.set_block(coords,
            blk,
        );
        placed.insert(coords, blk);
    }
    for (k, v) in placed.iter() {
        assert_eq!(world.get_block(*k), Some(*v));
    }
}

