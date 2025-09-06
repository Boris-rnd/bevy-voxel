@group(0) @binding(0) var<storage, read_write> max_depth: array<f32>;
@group(0) @binding(1) var<uniform> cam: Camera;
@group(0) @binding(2) var<storage, read> voxel_chunks: array<VoxelChunk>;
@group(0) @binding(3) var<storage, read> block_data0: array<MapData>;
@group(0) @binding(4) var<storage, read> block_data1: array<MapData>;
@group(0) @binding(5) var<storage, read> block_data2: array<MapData>;
@group(0) @binding(6) var<storage, read> block_data3: array<MapData>;

include! utils.wgsl
include! raytrace_common.wgsl



fn ray_depth(ray: Ray) -> f32 {
    var max_depth = 1e30;
    var depth = 0.;

    let root = voxel_chunks[0];
    let world_min = vec3<f32>(0.0);
    let world_max = vec3<f32>(f32(root_chunk_size()));

    // Intersect ray with root AABB
    var t = hit_box_t(ray, world_min, world_max);
    if t == INVALID_BOX_HIT {
        return max_depth;
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
    var bit_mask_for_chunk = array<u32, 2>();
    for (var iter = 0; iter < max_iter; iter = iter + 1) {
        // Query world at current integer voxel position
        let posi = vec3<i32>(posf);
        let parent_pos = parent_pos_stack[curr_depth - 1u];
        // Get chunk's child size as integer
        var child_size_i = i32(depth_to_chunk_size(curr_depth));
        let local_pos = div_euclid_v3(posi - parent_pos, vec3(child_size_i));
        
        if any((posi - parent_pos)<vec3(0)) || any(local_pos >= vec3(i32(CHUNK_SIZE))) {
            // Outside of previous chunk, if curr_depth==1, then outside of root chunk so won't hit anything else
            if curr_depth == 1u { 
                return 1e30;
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
                break;
            }
            // let curr_data = get_block_data(MapDataID(map_data_idx.array_array_idx, map_data_idx.array_idx)).data;
        
            let ty = curr_data & 3u;
            if ty == 1u { // Chunk, so we descend into it
                // Check if chunk is too small and beam has low resolution, if so, early exit to hide graphical artifacts
                if curr_depth > 2 && pc.beam_idx == 1u {
                    break;
                }
                idx_stack[curr_depth - 1u] = chunk_idx;
                parent_pos_stack[curr_depth] = parent_pos + vec3<i32>(
                    local_pos.x * child_size_i,
                    local_pos.y * child_size_i,
                    local_pos.z * child_size_i
                );
                curr_chunks[curr_chunks_len] = voxel_chunks[curr_data >> 2];
                if ((curr_chunks[curr_chunks_len].inner[0]&bit_mask_for_chunk[0]) == 0u) && ((curr_chunks[curr_chunks_len].inner[1]&bit_mask_for_chunk[1]) == 0u) && false {
                } else {
                    curr_chunks_len += 1u;
                    curr_depth += 1u;
                    continue; // IMPORTANT: re-evaluate at new depth
                }
            } else if ty == 2u { // Block
                break;
            }
        }
        // Should be useless check but I like to keep it
        // Check if we have found something
        // if map_data_idx.array_array_idx != 4294967295u {
        //     return valid_res(vec3(0., 1., 1.));
        // }
        var S = f32(child_size_i);
        if distance(ray.orig, posf)>1000 {
            S *= 2;
        }
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
    return ray_t_from_pos(ray, posf)-eps;
}



fn compute(global_id: vec2<u32>, prev_t: f32) -> f32 {
    if prev_t == 1e30 {
        return 1e30;
    }
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
    var r = Ray(orig, normalize(pixel_center - lookfrom));
    r.orig = at(r, prev_t);
    return ray_depth(r);
}
struct PushConstants {
    beam_idx: u32,
}
var<push_constant> pc: PushConstants;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let scale = 2u << pc.beam_idx; // 4 (i=1), 2 (i=0)
    let full_w = cam.img_size.x;
    let half_w = full_w >> 1u;

    // full-res coords processed by this invocation
    let x = global_id.x * scale;
    let y = global_id.y * scale;
    if (x >= cam.img_size.x || y >= cam.img_size.y) { return; }

    // map to half-res coords (what the final shader samples)
    let hx = x >> 1u;
    let hy = y >> 1u;

    // read seed from previous pass (¼→½): previous writes live at even cells
    var prev_t = 0.0;
    if (pc.beam_idx == 0u) {
        // current pass is ½-res; previous pass was ¼-res → even indices in half grid
        let prev_idx = (hx & ~1u) + ((hy & ~1u) * half_w);
        prev_t = max_depth[prev_idx];
    }
    let curr_idx = hx + hy * half_w;     // valid for both passes (¼ maps via hx/hy)

    let delta_t = compute(vec2<u32>(x, y), prev_t);
    max_depth[curr_idx] = prev_t + delta_t;   // <<< ACCUMULE
}