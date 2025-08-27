use crate::*;

#[derive(ShaderType)]
#[repr(C)]
#[derive(Default, Debug, Clone)]
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
#[derive(Default, Debug, Clone)]
pub struct Box {
    min: Vec3,
    max: Vec3,
    color: Vec3,
}
pub fn new_box(min: Vec3, max: Vec3, color: Vec3) -> Box {
    Box { min, max, color }
}
pub fn new_voxel(pos: Vec3) -> Box {
    new_box(
        pos - vec3(0.5, 0.5, 0.5),
        pos + vec3(0.5, 0.5, 0.5),
        vec3(1., 1., 1.),
    )
}

#[derive(ShaderType)]
#[repr(C)]
#[derive(Default, Debug, Clone)]
pub struct Voxel {
    pos: Vec3,
    texture_id: u32,
}
