use bevy::{prelude::*, render::render_resource::ShaderType};

#[derive(ShaderType)]
#[repr(C)]
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
pub struct Voxel {
    pos: Vec3,
    texture_id: u32,
}
#[derive(ShaderType)]
#[repr(C)]
pub struct VoxelChunk {
    pos: Vec3,
    inner1: u32,
    inner2: u32
}
pub fn voxel_chunk(pos: Vec3, voxels: u64) -> VoxelChunk {
    VoxelChunk { pos, inner2: (voxels&u32::MAX as u64) as u32, inner1: (voxels>>32) as u32 }
}

