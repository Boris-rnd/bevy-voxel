// #import bevy_sprite::{mesh2d_vertex_output::VertexOutput, mesh2d_view_bindings::globals}; 


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
include! utils.wgsl
include! raytrace_common.wgsl


// @group(2) @binding(100) var<uniform> cam.img_size: vec2<f32>;


fn hit_box_gen(ray: Ray, box: Box, chunk_idx: u32, chunk: VoxelChunk) -> HitRecord {
    var res = invalid_rec();

    var t = hit_box_t(ray, box.min, box.max);
    if t == INVALID_BOX_HIT {
        
        return valid_rec(vec3(1., 0., 0.)); // No hit
    }
    res.t = t;
    res.p = at(ray, t);
    let center = (box.min + box.max) / 2.;
    
    var uv: vec2<f32>;
    var data: u32 = box.texture_id;
    var light_intensity = vec3(1.);
    var circle_normal = center - res.p;
    var n = normalize(circle_normal);
    var abs_n = abs(n);

    // if abs_n.x >= abs_n.y && abs_n.x >= abs_n.z {
    //     circle_normal = vec3(sign(n.x), 0.0, 0.0);
    //     uv = res.p.zy;
    // } else if abs_n.y >= abs_n.x && abs_n.y >= abs_n.z {
    //     circle_normal = vec3(0.0, sign(n.y), 0.0);
    //     uv = res.p.xz;
    // } else {
    //     circle_normal = vec3(0.0, 0.0, sign(n.z));
    //     uv = res.p.xy;
    // }
    if circle_normal.x > abs(circle_normal.y) && circle_normal.x > abs(circle_normal.z) { uv = (circle_normal).zy; circle_normal = vec3(1., 0., 0.); } else if circle_normal.x < -abs(circle_normal.y) && circle_normal.x < -abs(circle_normal.z) { uv = (circle_normal).zy; circle_normal = vec3(-1., 0., 0.); } else if circle_normal.z > abs(circle_normal.y) && circle_normal.z > abs(circle_normal.x) { uv = (circle_normal).xy; circle_normal = vec3(0., 0., 1.); } else if circle_normal.z < -abs(circle_normal.y) && circle_normal.z < -abs(circle_normal.x) { uv = (circle_normal).xy; circle_normal = vec3(0., 0., -1.); } else if (circle_normal.y) > abs(circle_normal.x) && (circle_normal.y) > abs(circle_normal.z) { // Bottom face 
        uv = (circle_normal).xz; circle_normal = vec3(0., 1., 0.); } else if circle_normal.y < -abs(circle_normal.x) && circle_normal.y < -abs(circle_normal.z) { uv = (circle_normal).xz; circle_normal = vec3(0., -1., 0.); } else { circle_normal = vec3(1., 1.5, 1.); } res.normal = circle_normal;

    res.normal = circle_normal;
    res.t = t;
    // data = data%7;
    let r = data & 0xFF;
    let g = (data >> 8) & 0xFF;
    let b = (data >> 16) & 0xFF;
    let metallic = (data >> 24) & 1;
    res.color = vec3(f32(r) / 255., f32(g) / 255., f32(b) / 255.)*light_intensity;
    // if data > 5 {
    //     res.color = vec3(f32(data) / 255., f32(data) / 255., f32(data) / 255.);
    // } else {
    //     let texcoord = vec2<u32>((uv + vec2(0.5)) * 32.0);
    //     // let srgb = textureLoad(atlas, texcoord, data).xyz;
    //     let srgb = (textureLoad(atlas, texcoord, data).xyz - vec3(0.5)) * 1.2 + vec3(0.5);
    //     res.color = srgb_to_linear(srgb);
    //     if data==2 {
    //         res.color *= 4.;
    //     }
    // }
    return res;
}

fn set_bit_if_in_range(bit_mask: array<u32, CHUNK_U32_COUNT>, bit_pos: vec3<u32>) -> array<u32, CHUNK_U32_COUNT> {
    if (any(bit_pos >= vec3<u32>(CHUNK_SIZE))) {
        return bit_mask;
    }
    let chunk_idx = bit_pos.x | (bit_pos.y << CHUNK_SHIFT) | (bit_pos.z << (CHUNK_SHIFT * 2u));
    let word = chunk_idx / 32u;
    let bit = 1u << (chunk_idx % 32u);
    var b = bit_mask;
    b[word] = b[word] | bit;
    return b;
}

fn gen_chunk_mask(ray: Ray, start_pos_local: vec3<f32>) -> array<u32, CHUNK_U32_COUNT> {
    var posf = start_pos_local;
    let dir = ray.dir;
    let rcp = 1.0 / dir;
    var mask = array<u32, CHUNK_U32_COUNT>(4294967295, 4294967295);

    loop {
        // integer voxel inside chunk, safe conv via floor+clamp
        let pf = floor(posf);
        if any(pf<vec3(0.) || pf > vec3(f32(CHUNK_SIZE)-1.)) {break;}
        let posi = vec3<u32>(pf);

        // set current voxel and immediate forward neighbors (x+, y+, z+)
        mask = set_bit_if_in_range(mask, posi);
        mask = set_bit_if_in_range(mask, posi + vec3<u32>(1u, 0u, 0u));
        mask = set_bit_if_in_range(mask, posi + vec3<u32>(0u, 1u, 0u));
        mask = set_bit_if_in_range(mask, posi + vec3<u32>(0u, 0u, 1u));

        // compute distance to next voxel boundary along each axis (respect sign)
        let idxf = floor(posf);
        let next = select(idxf, idxf + vec3<f32>(1.0), dir > vec3<f32>(0.0));
        let tMax = (next - posf) * rcp;
        let tStep = min(tMax.x, min(tMax.y, tMax.z));

        // stop if non-finite or we will leave chunk
        if (!(tStep < 1e20)) { break; } // guard
        // step a little less than full boundary to avoid re-hitting same voxel due to float error
        let eps = 1e-4*4;
        posf = posf + dir * (tStep + eps);
    }
    return mask;
}

// // Changes light instensity to create fake shadows if block has neighbors on top left/right/front/back
// fn edge_chunk_shadows(rec: HitRecord, chunk_idx: u32, chunk: VoxelChunk, parent_chunk: VoxelChunk) -> HitRecord {
//     var res = rec;
//     let local_pos = local_pos_to_ivec3(chunk_idx);
//     if local_pos.x > 3 { // Check in neighbor chunks
//         let neighbor_chunk_idx = get_data_idx_in_chunk(parent_chunk, chunk_idx - 4);
//         if neighbor_chunk_idx.array_idx < arrayLengthBlockData(neighbor_chunk_idx.array_array_idx) {
//             let neighbor_data = get_block_data_follow_tails(neighbor_chunk_idx);
//             if neighbor_data != 4294967295u && (neighbor_data & 3u) == 2u {
//                 res.color *= 0.7;
//             }
//         }
//     } else {
//         // Use a bitmask on chunk's inner to check if neighbor exists
//         let neighbor_pos = ivec3_to_local_pos(local_pos + vec3(1, 1, 0));
//         if (chunk.inner[neighbor_pos / 32u] & (1u<<(neighbor_pos%32u))) != 0u {
//             res.color.r *= 10.7;
//         }
//     }
//     return res;
// }


fn local_pos_to_ivec3(idx: u32) -> vec3<u32> {
    let x = idx & u32(CHUNK_MASK);
    let y = (idx >> CHUNK_SHIFT) & u32(CHUNK_MASK);
    let z = (idx >> (CHUNK_SHIFT * 2u)) & u32(CHUNK_MASK);
    return vec3<u32>(x, y, z);
}
fn ivec3_to_local_pos(pos: vec3<u32>) -> u32 {
    return pos.x | (pos.y << CHUNK_SHIFT) | (pos.z << (CHUNK_SHIFT * 2u));
}
fn hit(ray: Ray) -> HitRecord {
    if (true) {return prev_hit(ray);}
    var miss = invalid_rec();

    // init posf inside world/root
    var posf = ray.orig;
    let world_min = vec3<f32>(0.0);
    let world_max = vec3<f32>(f32(root_chunk_size()));
    if (!(all(ray.orig > world_min) && all(ray.orig < world_max))) {
        let tbox = hit_box_t(ray, world_min, world_max);
        if (tbox == INVALID_BOX_HIT) { return miss; }
        posf = at(ray, tbox + 1e-3);
    }

    // stacks / context
    var curr_chunks = array<VoxelChunk, 6>();
    var parent_pos_stack: array<vec3<i32>, 7>;
    parent_pos_stack[0] = vec3<i32>(0); // Useless but might be usefull if change root chunk's origin
    var curr_depth: u32 = 1u;
    var curr_chunks_len: u32 = 1u;
    curr_chunks[0] = voxel_chunks[0];

    // DDA helpers
    let stepf = sign(ray.dir);
    let rcp = 1.0 / ray.dir;

    // iteration cap
    var max_iter = 50;
    if (is_accumulating_frames()) { max_iter = 50; }

    // compute initial mask for root chunk (posf relative to parent_pos)
    var child_size_i = i32(depth_to_chunk_size(curr_depth));
    var local_start = posf - vec3<f32>(parent_pos_stack[curr_depth - 1u]);
    var mask = gen_chunk_mask(ray, local_start / f32(child_size_i));

    var iter: i32 = 0;
    while iter < max_iter {
        if (iter>=max_iter) {break;}
        iter++;

        // combine mask with current chunk occupancy -> candidates
        var out = array<u32, CHUNK_U32_COUNT>();
        var any_hit = false;
        let curr_chunk = curr_chunks[curr_chunks_len - 1u];
        for (var i = 0u; i < CHUNK_U32_COUNT; i++) {
            out[i] = mask[i] & curr_chunk.inner[i];
            any_hit = any_hit || (out[i] != 0);
        }
        if (any_hit == false) {
            // advance along ray (DDA step) and recompute mask at same depth
            // compute child size for current depth
            child_size_i = i32(depth_to_chunk_size(curr_depth));
            let cell_size = i32(depth_to_chunk_size(curr_depth)) / i32(CHUNK_SIZE);
            let S = f32(cell_size);
            let posi = vec3<i32>(posf);
            let world_pos_in_parent = posf - vec3<f32>(parent_pos_stack[curr_depth - 1u]);
            let idxf = floor(world_pos_in_parent / S);
            let next = select(idxf * S, (idxf + vec3<f32>(1.0)) * S, stepf > vec3<f32>(0.0));
            var tMax = (next - world_pos_in_parent) * rcp;
            let tStep = min(tMax.x, min(tMax.y, tMax.z));
            if (!(tStep < 1e20)) { break; }
            let eps = 1e-3 * S;
            posf += ray.dir * (tStep + eps);
            // recompute mask for current chunk using new posf
            child_size_i = i32(depth_to_chunk_size(curr_depth));
            mask = gen_chunk_mask(ray, (posf - vec3<f32>(parent_pos_stack[curr_depth - 1u])) / f32(cell_size));
            continue;
        }

        // iterate candidate bits; clear lowest bit per word
        var descended = false;
        for (var i = 0u; i < CHUNK_U32_COUNT; i++) {
            while (out[i] != 0u) {
                let local_idx = countTrailingZeros(out[i]);
                // clear lowest set bit
                out[i] = out[i] & (out[i] - 1u);

                let idx = local_idx + 32u * i;
                let local3 = local_pos_to_ivec3(idx); // in [0..CHUNK_SIZE)
                // compute child origin in world coords (same formula as prev_hit)
                let child_size_here = i32(depth_to_chunk_size(curr_depth));
                let cell_origin = parent_pos_stack[curr_depth - 1u] + vec3<i32>(
                    i32(local3.x) * child_size_here,
                    i32(local3.y) * child_size_here,
                    i32(local3.z) * child_size_here
                );

                // quick AABB test at child cell level (child cell extent = child_size_here)
                let cell_min = vec3<f32>(cell_origin);
                let cell_max = vec3<f32>(cell_origin + vec3<i32>(child_size_here));
                let rec_t = hit_box_t(ray, cell_min, cell_max);
                if (rec_t == INVALID_BOX_HIT) { continue; }

                // lookup data for this local cell
                let map_data_idx = get_data_idx_in_chunk(curr_chunk, idx);
                if (map_data_idx.array_idx >= arrayLengthBlockData(map_data_idx.array_array_idx)) { continue; }
                let curr_data = get_block_data_follow_tails(map_data_idx);
                if (curr_data == 4294967295u) { continue; }
                let ty = curr_data & 3u;

                if (ty == 2u) {
                    // actual block -> compute precise hit and return
                    // use voxel-sized AABB (if child_size_here == 1), otherwise refine
                    // here we return the block hit
                    return valid_rec(vec3(0));
                    // return hit_box_gen(ray, Box(vec3<f32>(cell_origin), vec3<f32>(cell_origin + vec3<i32>(child_size_here)), curr_data >> 2u));
                } else if (ty == 1u) {
                    // descend into smaller chunk: push to stack and recompute mask for child
                    // update stacks
                    parent_pos_stack[curr_depth] = cell_origin;
                    curr_chunks[curr_chunks_len] = voxel_chunks[curr_data >> 2u];
                    curr_chunks_len = curr_chunks_len + 1u;
                    curr_depth = curr_depth + 1u;

                    // recompute mask for the new child chunk using same posf (relative to new child origin)
                    let next_child_size = i32(depth_to_chunk_size(curr_depth));
                    // local pos in child's coordinates = (posf - child_origin) / next_child_size
                    mask = gen_chunk_mask(ray, (posf - vec3<f32>(cell_origin)) / f32(next_child_size));
                    descended = true;
                    break; // break words loop to restart with new chunk context
                }
            }
            if (descended) { break; }
        }

        if (descended) { continue; }
        let cell_size = i32(depth_to_chunk_size(curr_depth)) / i32(CHUNK_SIZE);

        // If we processed all candidate bits and didn't descend or hit a block, advance ray
        child_size_i = i32(depth_to_chunk_size(curr_depth)) / i32(CHUNK_SIZE);
        let parent_pos = parent_pos_stack[curr_depth - 1u];
        let S = f32(cell_size);
        let world_pos_in_parent = posf - vec3<f32>(parent_pos);
        let idxf = floor(world_pos_in_parent / S);
        let next = select(idxf * S, (idxf + vec3<f32>(1.0)) * S, stepf > vec3<f32>(0.0));
        var tMax = (next - world_pos_in_parent) * rcp;
        let tStep = min(tMax.x, min(tMax.y, tMax.z));
        if (!(tStep < 1e20)) { break; }
        posf += ray.dir * (tStep + (1e-3 * S));

        // recompute mask for current depth after stepping
        mask = gen_chunk_mask(ray, (posf - vec3<f32>(parent_pos_stack[curr_depth - 1u])) / f32(cell_size));
        mask = array<u32, CHUNK_U32_COUNT>(4294967295, 4294967295);
    }

    return miss;
}



fn prev_hit(ray: Ray) -> HitRecord {
    var miss = invalid_rec();

    // Initialise ray inside root chunk
    var posf = ray.orig;
    let world_min = vec3<f32>(0.0);
    let world_max = vec3<f32>(f32(root_chunk_size()));
    if all(ray.orig > world_min) && all(ray.orig < world_max) {
        posf = ray.orig;
    } else {

        var t = hit_box_t(ray, world_min, world_max);
        if t == INVALID_BOX_HIT {
            return miss;
        }
        posf = at(ray, t + 1e-3);
    }

    // Setup stacks for the descent of sparse tree
    var curr_chunks = array<VoxelChunk, 6>();
    var parent_pos_stack: array<vec3<i32>, 7>;

    parent_pos_stack[0] = vec3<i32>(0);
    var curr_depth = 1u;
    var curr_chunks_len = 1u;
    curr_chunks[0] = voxel_chunks[0];
    var chunk_size = root_chunk_size();
    
    // Main traversal
    var stepf = sign(ray.dir);
    let rcp = 1. / ray.dir;




    // Hard cap to avoid infinite loops
    var max_iter = 500;
    if is_accumulating_frames() == true {
        max_iter = 1000;
    }
    var iter = 0;
    for (; iter < max_iter; iter = iter + 1) {
        let posi = vec3<i32>(posf);
        let parent_pos = parent_pos_stack[curr_depth - 1u];
        let child_size_i = i32(depth_to_chunk_size(curr_depth));
        let local_pos = div_euclid_v3(posi - parent_pos, vec3(child_size_i));
        // Check if outside of current chunk
        if any((posi - parent_pos) < vec3(0)) || any(local_pos >= vec3(i32(CHUNK_SIZE))) {
            // Outside of previous chunk, if curr_depth==1, then outside of root chunk so won't hit anything else
            if curr_depth == 1u { 
                break;
            }
            // Ascent
            curr_depth -= 1u;
            curr_chunks_len -= 1u;
            continue;
        }

        var chunk_idx = u32(local_pos.x) | (u32(local_pos.y) << CHUNK_SHIFT) | (u32(local_pos.z) << (CHUNK_SHIFT * 2));
        // Checks if bit is set, if so computes the idx, else returns U32::MAX (which will be bigger than arrayLength)
        let map_data_idx = get_data_idx_in_chunk(curr_chunks[curr_chunks_len - 1u], chunk_idx);
        if map_data_idx.array_idx < arrayLengthBlockData(map_data_idx.array_array_idx) {
            let curr_data = get_block_data_follow_tails(map_data_idx);
            if curr_data == 4294967295u { // Never happens but maybe one day i'll introduce a breaking bug
                return valid_rec(vec3(1., 0., 1.));
            }
            // let curr_data = get_block_data(MapDataID(map_data_idx.array_array_idx, map_data_idx.array_idx)).data;

            let ty = curr_data & 3u;
            if ty == 1u { // Chunk, so we descend into it
                parent_pos_stack[curr_depth] = parent_pos + vec3<i32>(
                    local_pos.x * child_size_i,
                    local_pos.y * child_size_i,
                    local_pos.z * child_size_i
                );
                curr_chunks[curr_chunks_len] = voxel_chunks[curr_data >> 2];
                curr_chunks_len += 1u;
                curr_depth += 1u;
                continue; // IMPORTANT: re-evaluate at new depth
            } else if ty == 2u { // Block
                var res = hit_box_gen(ray, Box(vec3<f32>(posi), vec3<f32>(posi) + vec3(1.0), u32(curr_data >> 2)), chunk_idx, curr_chunks[curr_chunks_len-1]);
                // res = edge_chunk_shadows(res, chunk_idx, curr_chunks[curr_chunks_len-1], curr_chunks[curr_chunks_len-2]);
                return res; // making posi = 0 and rb 10000 is fun
            }
        }
        // Should be useless check but I like to keep it
        // Check if we have found something
        if map_data_idx.array_array_idx != 4294967295u {
            return valid_rec(vec3(0., 1., 1.));
        }
        let S = f32(child_size_i);
        let world_pos_in_parent = posf - vec3<f32>(parent_pos);

        // handle zeros
        let inf = 1e30;
        let idxf = floor(world_pos_in_parent / S);
        let next = select(idxf * S, (idxf + vec3(1.)) * S, stepf > vec3(0.));
        var tMax = (next - world_pos_in_parent) * rcp;
        let tStep = min(tMax.x, min(tMax.y, tMax.z));
        if !(tStep < inf) {
            return valid_rec(vec3(1., 0., 1.));
        }

        // nudge with scale-aware epsilon
        let eps = (1e-3 * S)*(1. + f32(iter)/100.);
        posf += ray.dir * (tStep + eps);
    }
    if iter >= max_iter {
        return to_far_away_rec();
    }
    // return valid_rec(vec3(0., 0., f32(iter)/500.));
    return miss;
}
fn process_hit(ray: Ray, hit_result: HitRecord) -> HitRecord {
    var res = hit_result;
    
    // Lambertian shading - use abs or negate ray direction
    let light_dir = normalize(vec3<f32>(0.5, -1.0, 0.3)); // pick your sun dir
    let lambert = max(0.1, dot(res.normal, light_dir));
    let ray_lambert = max(0.1, dot(res.normal, ray.dir));
    res.color *= lambert*ray_lambert;
    // Distance-based fog (attenuate, don't add)
    let fog_distance = 4000.0;
    // let fog_factor = min(max(0.01, exp(1. - distance(cam.center, res.p) / fog_distance)), 1.);
    // res.color *= fog_factor;


    return res;
}
// Improved ray_color with better bounce handling
fn ray_color(initial_ray: Ray) -> vec3<f32> {
    var ray = initial_ray;
    var throughput = vec3<f32>(1.0);
    var final_color = vec3<f32>(0.0);
    let max_bounces = 5;

    for (var bounce = 0; bounce < max_bounces; bounce += 1) {
        var res = hit(ray);

        if (res.t == 1e30) {
            if all(res.p == vec3(1., 1., 1.)) {
                return vec3(1., 0., 0.); // Error color
            }
            // Sky contribution
            break;
        }

        res = process_hit(ray, res);
        // Material (simplified diffuse/metallic)
        let is_metallic = false;
        let roughness = 0.5;
        var next_dir: vec3<f32>;

        if (is_metallic) {
            next_dir = reflect(ray.dir, res.normal) + random_unit_vector() * roughness;
        } else {
            next_dir = normalize(res.normal + random_unit_vector());
            // return res.color;
        }

        // Update throughput (albedo * cosine term * 1/π for Lambertian)
        let cos_theta = max(dot(next_dir, res.normal), 0.0);
        throughput *= res.color * cos_theta;

        // Russian roulette
        let p = clamp(max(throughput.r, max(throughput.g, throughput.b)), 0.05, 1.0);
        if (rand(0.0, 1.0) > p && bounce > 2) { break; }
        throughput /= p;

        // Continue ray
        ray = Ray(res.p + next_dir * 0.001, next_dir);
    }
    final_color += throughput * skybox(ray.dir);
    if (true) {return final_color;}

    // Tonemap once
    return reinhard_tone_map(final_color);
}


// Better tone mapping function
fn reinhard_tone_map(color: vec3<f32>) -> vec3<f32> {
    // Extended Reinhard tone mapping
    let white_point = 2.0;
    let numerator = color * (1.0 + color / (white_point * white_point));
    let denominator = 1.0 + color;
    
    // Apply gamma correction
    return pow(numerator / denominator, vec3(1.0 / 2.2));
}
fn skybox(ray_dir: vec3<f32>) -> vec3<f32> {
    let a = 0.5 * (ray_dir.y + 1.0);
    var c = (1.0 - a) * vec3(1.0, 1.0, 1.0) + a * vec3(0.5, 0.7, 1.0);
    return c;
}

fn compute(global_id: vec2<u32>) {

    let i = f32(global_id.x);
    let j = (1. - f32(global_id.y) / f32(cam.img_size.y)) * f32(cam.img_size.y);
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
    var c = vec3(0.);

    let cam_seed = wang_hash(
        u32(abs(cam.center.x * 1000.0)) ^
        u32(abs(cam.center.y * 1000.0)) ^
        u32(abs(cam.center.z * 1000.0)) ^
        u32(abs(cam.direction.x * 1000.0)) ^
        u32(abs(cam.direction.y * 1000.0)) ^
        u32(abs(cam.direction.z * 1000.0))
    );
    init_rng(global_id.xy, cam.accum_frames, cam_seed);

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
        let depth_x = global_id.x / 2u;
        let depth_y = global_id.y / 2u;
        let depth_idx = depth_x + depth_y * (cam.img_size.x / 2);
        let prev_t = max_depth[depth_idx];
        // if prev_t == 1e30 {return;}
        // r.orig = at(r, prev_t);
        
        r.orig = at(r, max_depth[global_id.x/2+global_id.y/2*(cam.img_size.x/2)]);
        c += ray_color(r) / f32(samples_per_pixel);
    }
    
    c *= 255.;
    var out = vec4(vec3<u32>(c), 255u);
    out.r = min(out.r, 255u);
    out.g = min(out.g, 255u);
    out.b = min(out.b, 255u);
    out.a = min(out.a, 255u);
    let idx = global_id.x + global_id.y * (cam.img_size.x);
    let prev = accumulated_tex[idx];
    // out = u32(max_depth[idx]);
    let prev_v = vec4(prev & 0xffu, (prev >> 8u) & 0xffu, (prev >> 16u) & 0xffu, (prev >> 24u) & 0xffu);
    out = (prev_v * cam.accum_frames + out) / (cam.accum_frames + 1);
    accumulated_tex[idx] = (out.r) | ((out.g) << 8u) | ((out.b) << 16u) | ((out.a) << 24u);
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