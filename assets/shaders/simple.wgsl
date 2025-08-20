@group(0) @binding(0)
var<uniform> uni: f32;

@group(0) @binding(1)
var<storage, read_write> accumulated_tex: array<u32>;

@compute @workgroup_size(1)
fn main(@builtin(global_invocation_id) invocation_id: vec3<u32>) {
    accumulated_tex[invocation_id.x] = accumulated_tex[invocation_id.x] + u32(uni);
}