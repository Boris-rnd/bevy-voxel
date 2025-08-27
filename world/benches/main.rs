use world::*;

fn main() {
    // Run registered benchmarks.
    world_size(1024);
    // world_size(2048);
    // world_size(4096);
    // divan::main();
}

// Register a `fibonacci` function and benchmark it over multiple cases.
#[divan::bench(args = [512, 1024, 4, 8, 16, 32])]
fn world_size(n: u64) {
    let mut world = GameWorld::new(1024, 8);
    let mut placed = bevy::platform::collections::HashMap::new();
    for i in 0..n*10 {
        if i%1000==0{dbg!(i);}
        let coords = ivec3(
            ((rand::random::<f32>().abs() * 100.) as i32)%1000,
            ((rand::random::<f32>().abs() * 20.) as i32)%1000,
            ((rand::random::<f32>().abs() * 100.) as i32)%1000,
        );
        let blk = MapData::Block(rand::random::<u32>() % 15);
        world.set_block(coords, blk);
        placed.insert(coords, blk);
    }
    for (k, v) in placed.iter() {
        assert_eq!(world.get_block(*k), Some(*v));
    }

}
