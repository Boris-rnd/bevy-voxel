use bevy::prelude::*;
use bevy::render::RenderApp;
use bevy::utils::hashbrown::HashMap;
use noise::Perlin;

#[derive(Resource)]
pub struct World {
    generator: Perlin,
    diff: HashMap<IVec3, Tower>,
}
impl World {
    pub fn new(seed: u32) -> Self {
        Self {
            generator: Perlin::new(seed),
            diff: HashMap::default(),
        }
    }
    pub fn get_at(&self, coords: &IVec3) -> Tower {
        match self.diff.get(coords) {
            Some(tower) => *tower,
            None => {
                if coords.y <= self.get_height_at(coords.x, coords.y) {
                    Tower::Grass
                } else {Tower::Empty}
            },
        }
    }
    pub fn get_height_at(&self, x: i32, z: i32) -> i32 {
        (noise::NoiseFn::get(&self.generator, [x as f64/CHUNK_SIZED, z as f64/CHUNK_SIZED]) as f32*5.).round() as _
    }
}

pub const CHUNK_SIZE: usize = 32;
pub const CHUNK_SIZEI: i32 = CHUNK_SIZE as _;
pub const CHUNK_SIZED: f64 = CHUNK_SIZE as _;


#[derive(Debug, Clone, Copy, PartialEq, Hash)]
pub enum Tower {
    Empty,
    Dirt,
    Grass,
}

// impl std::hash::Hash for IVec3 {
//     fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
//         self.x.hash(state);
//         self.y.hash(state);
//         self.z.hash(state);
//     }
// }

pub struct WorldPlugin {}
impl Plugin for WorldPlugin {
    fn build(&self, app: &mut App) {
        let render = app.sub_app_mut(RenderApp);
        
    }
}
