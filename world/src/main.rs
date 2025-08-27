// Only for flamegraphs & testing

use bevy::platform::collections::HashMap;
use world::*;

#[cfg(feature = "dhat-heap")]
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

fn main() {
    #[cfg(feature = "dhat-heap")]
    let _profiler = dhat::Profiler::new_heap();
    // let mut start = std::time::Instant::now();
    let prev_world = gen_world_size(1024);

    // println!("Realloc count: {} \t Realloc count chunks: {}\n Mem usage: {} MB", &prev_world.realloc_count, &prev_world.realloc_count_chunks, prev_world.block_data.len()*std::mem::size_of::<MapData>()/1024/1024);
    // println!("Took {:?} to run", start.elapsed());
    // println!("-----\n");
    
    let mut start = std::time::Instant::now();
    let mut world: HashMap<IVec3, MapData> = HashMap::default();
    let perlin = noise::Perlin::new(1);
    for x in 0..prev_world.root_size() as i32 {
        if x%16==0 {
            print!("Done {}/{}\r", x, prev_world.root_size());
            std::io::Write::flush(&mut std::io::stdout()).unwrap();
        }
        for y in 1..3 {
            for z in 0..prev_world.root_size() as i32 {
                // if perlin.get([x as f64, y as f64, z as f64])>0.0 {
                world.insert(
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
    println!("Took {:?} to run", start.elapsed());
    println!("-----\n");
}
