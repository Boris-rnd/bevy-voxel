
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



// Make sure ray.dir is normalized and != 0
// We return x but we can use other components as well
// fn ray_t_from_pos(ray: Ray, pos: vec3<f32>) -> f32 {
//     return abs(((pos - ray.orig) / ray.dir).x);
// }
fn ray_t_from_pos(ray: Ray, pos: vec3<f32>) -> f32 {
    let d = abs(ray.dir);
    if d.x >= d.y && d.x >= d.z {
        return (pos.x - ray.orig.x) / ray.dir.x;
    } else if d.y >= d.z {
        return (pos.y - ray.orig.y) / ray.dir.y;
    } else {
        return (pos.z - ray.orig.z) / ray.dir.z;
    }
}