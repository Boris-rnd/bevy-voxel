@group(2) @binding(0) var<uniform> cam: Camera;
@group(2) @binding(1) var<storage, read> accumulated_tex: array<u32>;

#import bevy_sprite::mesh2d_vertex_output::VertexOutput;
#import bevy_sprite::mesh2d_view_bindings::globals;

// include! assets/shaders/utils.wgsl

struct Camera {
    center: vec3<f32>,
    direction: vec3<f32>,
    fov: f32,
    root_max_depth: u32,
    accum_frames: u32,
    img_size: vec2<u32>,
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = vec2<u32>(in.uv * vec2<f32>(cam.img_size));
    let idx = uv.x + uv.y * cam.img_size.x;
    var data = 0u;
    // if cam.accum_frames%2==0 { // Inverse from raytrace
    //     data = accumulated_tex2[idx];
    // } else {
    // }
    data = accumulated_tex[idx];
    // let data = accumulated_tex[u32((in.uv.x)*f32(cam.img_size.x)+in.uv.y*f32(cam.img_size.y)*f32(cam.img_size.x))];
    let r= data&0xffu;
    let g= (data>>8u)&0xffu;
    let b= (data>>16u)&0xffu;
    let a= (data>>24u)&0xffu;
    // if accumulated_tex[1000] == 0 {
    //     return vec4(0.);
    // } else {

    //     return vec4(1.);
    // }
    // return vec4(vec2<f32>(cam.img_size)/200./255., 0., 1.);
    return vec4(f32(r)/255., f32(g)/255., f32(b)/255., f32(a)/255.);
}
