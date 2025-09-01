@group(0) @binding(0) var<storage, read_write> max_depth: array<f32>;
@group(0) @binding(1) var<uniform> cam: Camera;
@group(0) @binding(2) var<storage, read> voxel_chunks: array<VoxelChunk>;
@group(0) @binding(3) var<storage, read> block_data0: array<MapData>;
@group(0) @binding(4) var<storage, read> block_data1: array<MapData>;
@group(0) @binding(5) var<storage, read> block_data2: array<MapData>;
@group(0) @binding(6) var<storage, read> block_data3: array<MapData>;

include! utils.wgsl
include! raytrace_common.wgsl



fn compute(global_id: vec2<u32>) -> f32 {
    let i = f32(global_id.x);
    let j = (1. - f32(global_id.y)/f32(cam.img_size.y)) * f32(cam.img_size.y);
    let lookfrom = cam.center;     // Point camera is looking from
    let lookat = cam.center + cam.direction;// Point camera is looking at
    let vup = vec3(0., 1., 0.); // Camera-relative "up" direction
    let defocus_angle = 5.;

    let vfov = cam.fov;

    let focal_length = 3.;
    let theta = degrees_to_radians(vfov);
    let h = tan(theta / 2);
    let viewport_height = 2. * h * focal_length;
    let viewport_width = viewport_height * (f32(cam.img_size.x) / f32(cam.img_size.y));

    let w = normalize(lookfrom - lookat);
    let u = normalize(cross(vup, w));
    let v = cross(w, u);

    let viewport_u = viewport_width * u; // Vector across viewport horizontal edge
    let viewport_v = viewport_height * (v); // Vector down viewport vertical edge
    
    // Calculate the horizontal and vertical delta vectors from pixel to pixel.
    let pixel_delta_u = viewport_u / f32(cam.img_size.x);
    let pixel_delta_v = viewport_v / f32(cam.img_size.y);

    // Calculate the location of the upper left pixel.
    let viewport_upper_left = lookfrom - focal_length * w - viewport_u / 2 - viewport_v / 2;
    let pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);



    rng_seed = f32((u32(f32(cam.accum_frames)))&(0xFF)) + (f32(global_id.x) + f32(global_id.y) * 10.);
    
    let pixel_center = pixel00_loc + ((i) * pixel_delta_u) + ((j) * pixel_delta_v);
    var orig = lookfrom;
    let r = Ray(orig, normalize(pixel_center - lookfrom));
    // while (true) {}
    return ray_depth(r);
}
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let x = global_id.x*2;
    let y = global_id.y*2;
    if x >= cam.img_size.x || y >= cam.img_size.y {
        return;
    }
    max_depth[global_id.x+global_id.y*(cam.img_size.x/2)] = compute(vec2<u32>(x, y));
}
