// #import bevy_sprite::{mesh2d_vertex_output::VertexOutput, mesh2d_view_bindings::globals}; 

include! assets/shaders/utils.wgsl

@group(0) @binding(0) var<storage, read_write> accumulated_tex: array<u32>;
@group(0) @binding(1) var<uniform> cam: Camera;
@group(0) @binding(2) var<storage, read> voxel_chunks: array<VoxelChunk>;
@group(0) @binding(3) var<storage, read> block_data: array<MapData>;
@group(0) @binding(4) var atlas: texture_storage_2d_array<rgba8unorm, read>;
// @group(0) @binding(5) var base_sampler: sampler;
@group(0) @binding(5) var<storage, read_write> accumulated_tex2: array<u32>;


// @group(2) @binding(100) var<uniform> cam.img_size: vec2<f32>;



struct DataResult {
    data: u32,
    depth: u32,
}
/// Returns root chunk data if not found
/// max depth starts at 1
/// Returns block_data, so also has the ty in first 2 bits
fn get_data_in_chunk(pos: vec3<i32>, chk: VoxelChunk, par_pos: vec3<i32>, dep: u32, max_depth: u32) -> DataResult {
    // if pos.x==1 {return u32(1);}
    // else {return u32(4294967295);} 
    var chunk = chk;
    var local_pos = vec3<i32>(0);
    var parent_pos = par_pos;
    var end_depth = dep;
    var curr_data = 1u; // Root chunk
    var prev_idx = 0u;
    for (var depth = dep; depth <= max_depth; depth++) {
        end_depth = depth;
        let chunk_size = i32(depth_to_chunk_size(depth-1));
        parent_pos += ((vec3<i32>(vec3(prev_idx & 3, (prev_idx >> 2) & 3, (prev_idx >> 4) & 3))) * chunk_size);
        local_pos = div_euclid_v3(pos - parent_pos, vec3<i32>(chunk_size >> 2));
        if any(local_pos >= vec3(4) || local_pos < vec3(0)) {return DataResult(0, 0);}
        var idx = u32(local_pos.x) + (u32(local_pos.y) << 2u) + u32((local_pos.z) << 4u);
        prev_idx = idx;

        let map_data_idx = get_data_idx_in_chunk(chunk, idx);
        if u32(map_data_idx) > arrayLength(&block_data) { // Also takes into account if map_data_idx == 4294967295u {break;}
            break; // Out of bounds
        }
        curr_data = block_data[map_data_idx].data;
        let ty = curr_data & 3;
        if ty == 2 { // Block
            return DataResult(curr_data, u32(depth)); // Return texture id
        } else if ty == 1 { // Chunk
            // return set_bits; // Return texture id
            chunk = voxel_chunks[curr_data >> 2];
        } else { // Error
            // return u32(4294967295); // u32::MAX
            break;
        }
    }
    // Returns root chunk if nothing found or latest chunk
    return DataResult(curr_data, u32(end_depth));
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
    for (var iter = 0; iter < max_iter; iter = iter + 1) {
        // Query world at current integer voxel position
        let posi = vec3<i32>(floor(posf));
        let parent_pos = parent_pos_stack[curr_depth - 1u];
        let child_size_i = i32(depth_to_chunk_size(curr_depth));
        let local_pos = div_euclid_v3(posi - parent_pos, vec3(child_size_i));
        if any((posi - parent_pos)<vec3(0)) || any(local_pos >= vec3(4)) {
            if curr_depth == 1u { 
                break;
             }
            curr_depth -= 1u;
            curr_chunks_len -= 1u;
            continue;
        }

        var chunk_idx = u32(local_pos.x) | (u32(local_pos.y) << 2u) | (u32(local_pos.z) << 4u);
        let map_data_idx = get_data_idx_in_chunk(curr_chunks[curr_chunks_len - 1u], chunk_idx);
        if map_data_idx < arrayLength(&block_data) {
            let curr_data = get_block_data_follow_tails(map_data_idx);
            if curr_data == 4294967295u {
                break;
            }
            let ty = curr_data & 3u;

            if ty == 1u {
                // descend
                idx_stack[curr_depth - 1u] = chunk_idx;
                parent_pos_stack[curr_depth] = parent_pos + vec3<i32>(
                    local_pos.x * child_size_i,
                    local_pos.y * child_size_i,
                    local_pos.z * child_size_i
                );
                curr_chunks[curr_chunks_len] = voxel_chunks[curr_data >> 2];
                curr_chunks_len += 1u;
                curr_depth += 1u;
                continue; // IMPORTANT: re-evaluate at new depth
            } else if ty == 2u {
                // break;
                return hit_box_gen(ray, Box(vec3<f32>(posi), vec3<f32>(posi) + vec3(1.0), u32(curr_data>>2))); // making posi = 0 and rb 10000 is fun
            }
        }
        if map_data_idx != 4294967295u {
            return valid_res(vec3(0., 1., 0.));
        }
        // if (true) {continue;}
        let S = f32(max(1, child_size_i));               // size of a child cell at current depth
        let world_pos_in_parent = posf-vec3<f32>(parent_pos);

        // handle zeros
        let inf = 1e30;
        let normed = world_pos_in_parent / S; 
        var idxf = div_euclid_f32_v3(world_pos_in_parent, vec3(f32(S)));
        idxf = floor(normed);
        // idxf = floor(world_pos_in_parent)*S;
        let next = select(idxf*S, (idxf+vec3(1.))*S, stepf>vec3(0.));

        var tMax = select(vec3(inf), (next - world_pos_in_parent) * rcp, dir != vec3(0.));

        let tStep = min(tMax.x, min(tMax.y, tMax.z));
        if !(tStep < inf) { 
            return valid_res(vec3(0., 0., 1.));
         }

        // nudge with scale-aware epsilon
        let eps = 1e-3 * max(1.0, S);
        posf += dir * (tStep + eps);
    }

    return miss;
}

const INVALID_BOX_HIT: f32 = 3*10e10;
fn hit_box_t(ray: Ray, bmin: vec3<f32>, bmax: vec3<f32>) -> f32 {
    let t135 = (bmax - ray.orig) / ray.dir;
    let t246 = (bmin - ray.orig) / ray.dir;

    let tmin = max(max(min(t135.x, t246.x), min(t135.y, t246.y)), min(t135.z, t246.z));
    let tmax = min(min(max(t135.x, t246.x), max(t135.y, t246.y)), max(t135.z, t246.z));

    if tmin > tmax || tmax < 0 {
        return INVALID_BOX_HIT;
    }
    return tmin;
}

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
    data = data%7;
    if data > 5 {
        res.rec.color = vec3(0., f32(data) / 255., 0.);
    } else {
        let texcoord = vec2<u32>((uv + vec2(0.5)) * 32.0);
        let srgb = textureLoad(atlas, texcoord, data).xyz;
        res.rec.color = srgb_to_linear(srgb);
    }
    return res;
}
fn ray_color(ray2: Ray) -> vec3<f32> {
    var ray = ray2;

    let unit_direction = normalize(ray.dir);
    let a = 0.5 * (unit_direction.y + 1.0);
    var c = (1.0 - a) * vec3(1.0, 1.0, 1.0) + a * vec3(0.5, 0.7, 1.0);
    // c *= c*c*vec3(0.5, 0., 0.);

    for (var i = 1; i < 10; i += 10) {
        var res = hit(ray);
        if res.valid {
            // if is_accumulating_frames() == false {
            if true {
                return res.rec.color;
            }
            // var direction = res.rec.normal + random_unit_vector() * 0.5;
            var direction = reflect(ray.dir, res.rec.normal) + random_unit_vector()*0.2;
            if near_zero(direction) {direction = res.rec.normal;}
            // c = (c*0.1)+res.rec.color;
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
        let r = Ray(orig, pixel_center - lookfrom);
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