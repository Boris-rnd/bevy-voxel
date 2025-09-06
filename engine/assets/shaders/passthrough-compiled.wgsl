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

fn fetch(idx: u32) -> vec4<f32> {
    let data = accumulated_tex[idx];
    let r= data&0xffu;
    let g= (data>>8u)&0xffu;
    let b= (data>>16u)&0xffu;
    let a= (data>>24u)&0xffu;
    return vec4<f32>(vec4(r,g,b,a));
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = vec2<u32>(in.uv * vec2<f32>(cam.img_size));
    let idx = u32(uv.x + uv.y * u32(cam.img_size.x));
    // // var data = 0u;
    // var data = fetch(idx);
    var data = (fetch(idx)+fetch(idx+1)+fetch(idx-1)+fetch(idx+cam.img_size.x)+fetch(idx-cam.img_size.x))/5;
    let r= data.x;
    let g= data.y;
    let b= data.z;
    let a= data.w;
    return vec4(f32(r)/255., f32(g)/255., f32(b)/255., f32(a)/255.);
    // let f_xy = fract(uv);
    // let fred = fetch(idx) * (1 - f_xy.x) + fetch(idx + 1) * f_xy.x;
    // let fred_below = vec4(0.);
    // let fg = fred * (1 - f_xy.y) + fred_below * f_xy.y;
    // return vec4<f32>(fg.rgb / 255., 1.0);
}