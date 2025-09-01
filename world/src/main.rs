// Only for flamegraphs & testing

use bevy::platform::collections::HashMap;
use world::*;

#[cfg(feature = "dhat-heap")]
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

fn main() {
    #[cfg(feature = "dhat-heap")]
    let _profiler = dhat::Profiler::new_heap();
    // let start = std::time::Instant::now();
    // let prev_world = gen_world_size(1024);

    // println!("Realloc count: {} \t Realloc count chunks: {}\n Mem usage: {} MB", &prev_world.realloc_count, &prev_world.realloc_count_chunks, prev_world.block_data.len()*std::mem::size_of::<MapData>()/1024/1024);
    // println!("Took {:?} to run", start.elapsed());
    // println!("-----\n");
    
    let start = std::time::Instant::now();
    gen_world();
    println!("Took {:?} to run", start.elapsed());
    println!("-----\n");
}
