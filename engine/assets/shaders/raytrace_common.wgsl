
// #ifdef _CHUNK_SIZE
//     const CHUNK_SIZE: u32 = _CHUNK_SIZE;
// #endif
const CHUNK_U32_COUNT = CHUNK_SIZE*CHUNK_SIZE*CHUNK_SIZE/32;
// const CHUNK_U32_COUNT = 1;
const CHUNK_SIZE: u32 = #{_CHUNK_SIZE};
const CHUNK_MASK = CHUNK_SIZE - 1u;
const CHUNK_SHIFT = countOneBits(CHUNK_MASK);

struct DataResult {
    data: u32,
    depth: u32,
}
/// Returns root chunk data if not found
/// max depth starts at 1
/// Returns block_data, so also has the ty in first 2 bits
// fn get_data_in_chunk(pos: vec3<i32>, chk: VoxelChunk, par_pos: vec3<i32>, dep: u32, max_depth: u32) -> DataResult {
//     // if pos.x==1 {return u32(1);}
//     // else {return u32(4294967295);} 
//     var chunk = chk;
//     var local_pos = vec3<i32>(0);
//     var parent_pos = par_pos;
//     var end_depth = dep;
//     var curr_data = 1u; // Root chunk
//     var prev_idx = 0u;
//     for (var depth = dep; depth <= max_depth; depth++) {
//         end_depth = depth;
//         let chunk_size = i32(depth_to_chunk_size(depth-1));
//         parent_pos += ((vec3<i32>(vec3(prev_idx & 3, (prev_idx >> 2) & 3, (prev_idx >> 4) & 3))) * chunk_size);
//         local_pos = div_euclid_v3(pos - parent_pos, vec3<i32>(chunk_size >> 2));
//         if any(local_pos >= vec3(4) || local_pos < vec3(0)) {return DataResult(0, 0);}
//         var idx = u32(local_pos.x) + (u32(local_pos.y) << CHUNK_SHIFT) + u32((local_pos.z) << (CHUNK_SHIFT*2));
//         prev_idx = idx;

//         let map_data_idx = get_data_idx_in_chunk(chunk, idx);
//         if u32(map_data_idx) > arrayLength(&block_data) { // Also takes into account if map_data_idx == 4294967295u {break;}
//             break; // Out of bounds
//         }
//         curr_data = block_data[map_data_idx].data;
//         let ty = curr_data & 3;
//         if ty == 2 { // Block
//             return DataResult(curr_data, u32(depth)); // Return texture id
//         } else if ty == 1 { // Chunk
//             // return set_bits; // Return texture id
//             chunk = voxel_chunks[curr_data >> 2];
//         } else { // Error
//             // return u32(4294967295); // u32::MAX
//             break;
//         }
//     }
//     // Returns root chunk if nothing found or latest chunk
//     return DataResult(curr_data, u32(end_depth));
// }

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
    var max_iter = 50;
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
                return ray_t_from_pos(ray, posf)-eps;
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
                    curr_chunks_len += 1u;
                    curr_depth += 1u;
                    continue; // IMPORTANT: re-evaluate at new depth
                }
            } else if ty == 2u { // Block
                return ray_t_from_pos(ray, posf)-eps;
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

    return max_depth;
}

// Make sure ray.dir is normalized and != 0
// We return x but we can use other components as well
fn ray_t_from_pos(ray: Ray, pos: vec3<f32>) -> f32 {
    return ((pos - ray.orig) / ray.dir).x;
}
