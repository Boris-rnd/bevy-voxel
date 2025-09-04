// #import bevy_sprite::{mesh2d_vertex_output::VertexOutput, mesh2d_view_bindings::globals}; 
// import super::utils::*;
// import super::raytrace_common::*;

@group(0) @binding(0) var<storage, read_write> accumulated_tex: array<u32>;
@group(0) @binding(1) var<uniform> cam: Camera;
@group(0) @binding(2) var<storage, read> max_depth: array<f32>;
@group(0) @binding(3) var atlas: texture_storage_2d_array<rgba8unorm, read>;
@group(0) @binding(4) var<storage, read> voxel_chunks: array<VoxelChunk>;
@group(0) @binding(5) var<storage, read> block_data0: array<MapData>;
@group(0) @binding(6) var<storage, read> block_data1: array<MapData>;
@group(0) @binding(7) var<storage, read> block_data2: array<MapData>;
@group(0) @binding(8) var<storage, read> block_data3: array<MapData>;

// @group(0) @binding(5) var base_sampler: sampler;
// include! utils.wgsl
// include! raytrace_common.wgsl


#import super::utils::{
    div_euclid_v3,
    div_euclid,
    div_euclid_f32,
    div_euclid_f32_v3,
    rem_euclid,
    rem_euclid_v3,
    degrees_to_radians,
    near_zero,
    reflect,
    random_unit_vector,
    random_on_hemisphere,
    random_in_unit_disk,
    xorshift_rand,
    xorshift_randf32,
    wang_hash,
    rand_01_wang,
    rand_01,
    rand,
    vec3_rand,
    set_face_normal,
    cmple,
    cmple_to_unit,
    cmple,
    fastFloor,
    count_bits_in_range,
    branchless_dda,
    chunk_depth_to_size,
    depth_to_chunk_size,
    root_chunk_size,
    srgb_to_linear,
    is_accumulating_frames,
    size_to_array_array_idx,
    array_array_idx_to_prefix_size,
    get_block_data,
    arrayLengthBlockData,
    get_data_idx_in_chunk,
    get_block_data_follow_tails,
    valid_res,
    count_ones,
    at,
    local_pos,
    ivec3_local_pos,
};
#import super::raytrace_common::{
    get_data_in_chunk,
    hit_box_t,
    ray_depth,
    ray_t_from_pos,
    INVALID_BOX_HIT,
};

// @group(2) @binding(100) var<uniform> cam.img_size: vec2<f32>;


fn hit_box_gen(ray: Ray, box: Box) -> HitRecordResult {
    var res = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));

    var t = hit_box_t(ray, box.min, box.max);
    if t == INVALID_BOX_HIT {
        return res; // No hit
    }
    res.valid = true;
    res.rec.p = at(ray, t);
    let center = (box.min + box.max) / 2.;
    var circle_normal = center - res.rec.p;

    var uv: vec2<f32>;
    var data: u32 = box.texture_id;
    if circle_normal.x > abs(circle_normal.y) && circle_normal.x > abs(circle_normal.z) {
        uv = (circle_normal).zy;
        circle_normal = vec3(1., 0., 0.);
    } else if circle_normal.x < -abs(circle_normal.y) && circle_normal.x < -abs(circle_normal.z) {
        uv = (circle_normal).zy;
        circle_normal = vec3(-1., 0., 0.);
    } else if circle_normal.z > abs(circle_normal.y) && circle_normal.z > abs(circle_normal.x) {
        uv = (circle_normal).xy;
        circle_normal = vec3(0., 0., 1.);
    } else if circle_normal.z < -abs(circle_normal.y) && circle_normal.z < -abs(circle_normal.x) {
        uv = (circle_normal).xy;
        circle_normal = vec3(0., 0., -1.);
    } else if circle_normal.y > abs(circle_normal.x) && circle_normal.y > abs(circle_normal.z) {
        uv = (circle_normal).xz;
        circle_normal = vec3(0., 1., 0.);
        // data = 1;
    } else if circle_normal.y < -abs(circle_normal.x) && circle_normal.y < -abs(circle_normal.z) {
        uv = (circle_normal).xz;
        circle_normal = vec3(0., -1., 0.);
        // data = 1;
    } else {
        circle_normal = vec3(1., 1.5, 1.);
    }
    res.rec.normal = circle_normal;
    res.rec.t = t;
    res.rec.front_face = false;
    // data = data%7;
    if data > 5 {
        res.rec.color = vec3(0., f32(data) / 255., f32(data) / 255.);
    } else {
        let texcoord = vec2<u32>((uv + vec2(0.5)) * 32.0);
        let srgb = textureLoad(atlas, texcoord, data).xyz;
        res.rec.color = srgb_to_linear(srgb);
        if data==2 {
            res.rec.color *= 4.;
        }
    }
    return res;
}
fn hit(ray: Ray) -> HitRecordResult {
    var miss = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));

    let root = voxel_chunks[0];
    let world_min = vec3<f32>(0.0);
    let world_max = vec3<f32>(f32(root_chunk_size()));

    // Intersect ray with root AABB
    var t = hit_box_t(ray, world_min, world_max);
    if t == INVALID_BOX_HIT {
        return miss;
    }

    // Start just inside
    var posf = at(ray, t + 1e-3);
    if all(ray.orig > world_min) && all(ray.orig < world_max) {
        posf = ray.orig;
    }

    let dir = ray.dir;
    let rcp = (1.0 / dir);
    let stepf = sign(dir); // select(vec3(-1.0), vec3(1.0), ray.dir > vec3(0.0))
    let step = vec3<i32>(stepf);        // for index stepping

    // Clamp a to multiples of S in the correct direction
    let eps = 5e-3;

    // Curr_chunk = curr_chunks[curr_chunks_len-1]
    var curr_chunks = array<VoxelChunk, 6>();
    var parent_pos_stack: array<vec3<i32>, 7>;
    var idx_stack: array<u32, 7>;
    parent_pos_stack[0] = vec3<i32>(0);
    var curr_depth = 1u;
    var curr_chunks_len = 1u;
    curr_chunks[0] = root;

    var small_tstep_count = 0;

    // Main traversal
    // Hard cap to avoid infinite loops in degenerate cases
    var max_iter = 500;
    if is_accumulating_frames() == true {
        max_iter = 1000;
    }
    var bit_mask_for_chunk = array<u32, 2>();
    for (var iter = 0; iter < max_iter; iter = iter + 1) {
        // Query world at current integer voxel position
        let posi = vec3<i32>(posf);
        let parent_pos = parent_pos_stack[curr_depth - 1u];
        // Get chunk's child size as integer
        let child_size_i = i32(depth_to_chunk_size(curr_depth));
        let local_pos = div_euclid_v3(posi - parent_pos, vec3(child_size_i));
        if any((posi - parent_pos)<vec3(0)) || any(local_pos >= vec3(i32(CHUNK_SIZE))) {
            // Outside of previous chunk, if curr_depth==1, then outside of root chunk so won't hit anything else
            if curr_depth == 1u { 
                break;
            }
            // Ascent
            curr_depth -= 1u;
            curr_chunks_len -= 1u;
            continue;
        }

        var chunk_idx = u32(local_pos.x) | (u32(local_pos.y) << CHUNK_SHIFT) | (u32(local_pos.z) << (CHUNK_SHIFT*2));
        bit_mask_for_chunk[chunk_idx/32u] = bit_mask_for_chunk[chunk_idx/32u] | (1u << (chunk_idx % 32u));
        let map_data_idx = get_data_idx_in_chunk(curr_chunks[curr_chunks_len - 1u], chunk_idx);
        // Checks if bit is set, if so computes the idx, else returns U32::MAX (which will be bigger than arrayLength)
        if map_data_idx.array_idx < arrayLengthBlockData(map_data_idx.array_array_idx) {
            let curr_data = get_block_data_follow_tails(map_data_idx);
            if curr_data == 4294967295u { // Never happens but maybe one day i'll introduce a breaking bug
                return valid_res(vec3(1., 0., 1.));
            }
            // let curr_data = get_block_data(MapDataID(map_data_idx.array_array_idx, map_data_idx.array_idx)).data;
        
            let ty = curr_data & 3u;
            if ty == 1u { // Chunk, so we descend into it
                idx_stack[curr_depth - 1u] = chunk_idx;
                parent_pos_stack[curr_depth] = parent_pos + vec3<i32>(
                    local_pos.x * child_size_i,
                    local_pos.y * child_size_i,
                    local_pos.z * child_size_i
                );
                curr_chunks[curr_chunks_len] = voxel_chunks[curr_data >> 2];
                if ((curr_chunks[curr_chunks_len].inner[0]&bit_mask_for_chunk[0]) == 0u) && ((curr_chunks[curr_chunks_len].inner[1]&bit_mask_for_chunk[1]) == 0u) {
                } else {
                }
                curr_chunks_len += 1u;
                curr_depth += 1u;
                continue; // IMPORTANT: re-evaluate at new depth
            } else if ty == 2u { // Block
                return hit_box_gen(ray, Box(vec3<f32>(posi), vec3<f32>(posi) + vec3(1.0), u32(curr_data>>2))); // making posi = 0 and rb 10000 is fun
            }
        }
        // Should be useless check but I like to keep it
        // Check if we have found something
        // if map_data_idx.array_array_idx != 4294967295u {
        //     return valid_res(vec3(0., 1., 1.));
        // }
        let S = f32(child_size_i);
        let world_pos_in_parent = posf - vec3<f32>(parent_pos);

        // handle zeros
        let inf = 1e30;
        let idxf = floor(world_pos_in_parent / S);
        let next = select(idxf*S, (idxf+vec3(1.))*S, stepf>vec3(0.));
        var tMax = (next - world_pos_in_parent) * rcp;
        let tStep = min(tMax.x, min(tMax.y, tMax.z));
        // if !(tStep < inf) { 
        //     return valid_res(vec3(1., 0., 1.));
        //  }

        // nudge with scale-aware epsilon
        let eps = 1e-3 * S;
        posf += dir * (tStep + eps);
    }

    return miss;
}
fn ray_color(ray2: Ray) -> vec3<f32> {
    var ray = ray2;

    let a = 0.5 * (ray.dir.y + 1.0);
    var c = (1.0 - a) * vec3(1.0, 1.0, 1.0) + a * vec3(0.5, 0.7, 1.0);

    for (var i = 1; i < 3; i += 1) {
        var res = hit(ray);
        if res.valid {
            if is_accumulating_frames() == false {
            // if true {
                return res.rec.color;
            }
            // var direction = res.rec.normal + random_unit_vector() * 0.5;
            var direction = reflect(ray.dir, res.rec.normal) + random_unit_vector()*0.2;
            if near_zero(direction) {direction = res.rec.normal;}
            c *= res.rec.color;
            ray = Ray(res.rec.p, direction);
        } else {
            return c;
        }
    }
    return c;
}


fn compute(global_id: vec2<u32>) {
    
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


    let defocus_radius = focal_length * tan(degrees_to_radians(defocus_angle / 2));
    let defocus_disk_u = u * defocus_radius;
    let defocus_disk_v = v * defocus_radius;

    let focus = false;

    var samples_per_pixel = 1;
    if is_accumulating_frames() {
        samples_per_pixel = 2;
    }
    var antialiasing = false;
    if samples_per_pixel > 1 {antialiasing = true;}
    var c = vec3(0.);
    rng_seed = f32((u32(f32(cam.accum_frames)))&(0xFF)) + (f32(global_id.x) + f32(global_id.y) * 10.);
    for (var s = 0; s < samples_per_pixel; s++) {
        var offset = vec3(0.);
        if samples_per_pixel > 1 {
            let offset_x = rand(-0.5, 0.5);
            let offset_y = rand(-0.5, 0.5);
            offset = vec3(offset_x, offset_y, 0.);
        }
        let pixel_center = pixel00_loc + ((i + offset.x) * pixel_delta_u) + ((j + offset.y) * pixel_delta_v);
        var orig = lookfrom;
        if focus {
            let p = random_in_unit_disk();
            orig += (p.x * defocus_disk_u) + (p.y * defocus_disk_v);
        }
        var r = Ray(orig, normalize(pixel_center - lookfrom));
        r.orig = at(r, max_depth[global_id.x/2+global_id.y/2*(cam.img_size.x/2)]);
        c += ray_color(r) / f32(samples_per_pixel);
    }
    



    // c = vec3(rand_05_centered());
    // let texcoord = vec2(i32(global_id.x), i32(global_id.y * cam.img_size.y));
    // c = cam.direction;
    c *= 255.;
    var out = vec4(vec3<u32>(abs(c)), 255u);
    // out.r = u32(cam.img_size.x/100);
    // out.g = u32(cam.img_size.y/100);
    // out.b = u32(u32(cam.accum_frames));
    // var out = vec4(0, 0, 0, 255u);
    // var out = vec4(global_id, 255u);
    out.r = min(out.r, 255u);
    out.g = min(out.g, 255u);
    out.b = min(out.b, 255u);
    out.a = min(out.a, 255u);
    let prev = accumulated_tex[global_id.x+global_id.y*(cam.img_size.x)];
    let prev_v= vec4(prev&0xffu, (prev>>8u)&0xffu,  (prev>>16u)&0xffu,  (prev>>24u)&0xffu);
    out = (prev_v*cam.accum_frames + out) / (cam.accum_frames + 1);
    accumulated_tex[global_id.x+global_id.y*(cam.img_size.x)] = (out.r) | ((out.g) << 8u) | ((out.b) << 16u) | ((out.a) << 24u);
    // accumulated_tex[global_id.x+global_id.y*(cam.img_size.x)] = cam.accum_frames;
    if cam.accum_frames%2==0 {
    // out = (textureLoad(accumulated_img, texcoord) * f32(cam.accum_frames) + out) / f32(cam.accum_frames + 1);
    } else {
        // accumulated_tex2[global_id.x+global_id.y*(cam.img_size.x)] = (out.r) | ((out.g) << 8u) | ((out.b) << 16u) | ((out.a) << 24u);
    }
}
// const WORKGROUP_SIZE: u32 = 8;
// @compute @workgroup_size(WORKGROUP_SIZE, WORKGROUP_SIZE, 1)
// fn main(
//     @builtin(global_invocation_id) global_id: vec3<u32>,
//     @builtin(num_workgroups) workgroup_count: vec3<u32>,
// ) {
//     let size_per_invoke = vec2<f32>(cam.img_size)/(vec2(f32(WORKGROUP_SIZE))*vec2<f32>(workgroup_count.xy));
//     let normed = vec2<f32>(global_id.xy)/(vec2(f32(WORKGROUP_SIZE))*vec2<f32>(workgroup_count.xy));
    
//     let local_global_id_start = normed*vec2<f32>(cam.img_size);
//     let local_global_id_end = local_global_id_start + size_per_invoke;
//     for (var i = u32(local_global_id_start.x); i < u32(local_global_id_end.x); i += 1) {
//         for (var j = u32(local_global_id_start.y); j < u32(local_global_id_end.y); j += 1) {
//             compute(vec2(i, j));
//         }
//     }
// }
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let x = global_id.x;
    let y = global_id.y;
    if x >= cam.img_size.x || y >= cam.img_size.y {
        return;
    }
    compute(vec2<u32>(x, y));
}