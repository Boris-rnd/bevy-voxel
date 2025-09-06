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
// utils.wgsl
// Utility functions for WGSL shaders
fn div_euclid_v3(a: vec3<i32>, b: vec3<i32>) -> vec3<i32> {
    return vec3(div_euclid(a.x, b.x), div_euclid(a.y, b.y), div_euclid(a.z, b.z));
}

fn div_euclid(a: i32, b: i32) -> i32 {
    let q = a / b;
    let r = a % b;
    return q - select(0, 1, (r < 0) && (b > 0)) + select(0, 1, (r > 0) && (b < 0));

}fn div_euclid_f32(a: f32, b: f32) -> f32 {
    let q = floor(a / b);
    return select(q - 1.0, q, a >= 0.0);

    // let q = a / b;
    // let r = a % b;
    // return q - select(0., 1., (r < 0.) && (b > 0.)) + select(0., 1., (r > 0) && (b < 0));
}

fn div_euclid_f32_v3(a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        div_euclid_f32(a.x, b.x),
        div_euclid_f32(a.y, b.y),
        div_euclid_f32(a.z, b.z),
    );
}
fn rem_euclid(a: i32, b: i32) -> i32 {
    let r = a % b;
    return select(r, r + abs(b), r < 0);
}
fn rem_euclid_v3(a: vec3<i32>, b: vec3<i32>) -> vec3<i32> {
    return vec3(rem_euclid(a.x, b.x), rem_euclid(a.y, b.y), rem_euclid(a.z, b.z));
}
fn degrees_to_radians(deg: f32) -> f32 {
    return deg / 180. * 3.14159;
}

fn near_zero(v: vec3<f32>) -> bool {
    // Return true if the vector is close to zero in all dimensions.
    let s = 1e-8;
    return (abs(v.x) < s) && (abs(v.y) < s) && (abs(v.z) < s);
}
fn reflect(v: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    return v - 2. * dot(v, n) * n;
}

var<private> rng_seed: f32 = 1.;

fn random_unit_vector() -> vec3<f32> {
    for (var i = 0; i < 5; i++) {
        let p = vec3_rand(-1., 1.);
        let lensq = dot(p, p);
        if 1e-160 < lensq && lensq <= 1 {
            return p / sqrt(lensq);
        }
    }
    return vec3(0.);
}

fn random_on_hemisphere(normal: vec3<f32>) -> vec3<f32> {
    let on_unit_sphere = random_unit_vector();
    if dot(on_unit_sphere, normal) > 0.0 { // In the same hemisphere as the normal
        return on_unit_sphere;
    } else {
        return -on_unit_sphere;
    }
}


fn random_in_unit_disk() -> vec3<f32> {
    for (var i = 0; i < 5; i++) {
        let p = vec3(rand(-1., 1.), rand(-1., 1.), 0.);
        if dot(p, p) < 1. {
            return p;
        }
    }
    return vec3(0.);
}
var<private> rng_state: u32;

// Initialize RNG state based on pixel coordinates and frame number
fn init_rng(pixel: vec2<u32>, frame: u32) {
    // Combine pixel coordinates and frame into a unique seed
    rng_state = wang_hash(pixel.x + wang_hash(pixel.y + wang_hash(frame)));
}

// Improved Wang hash function
fn wang_hash(seed: u32) -> u32 {
    var s = seed;
    s = (s ^ 61u) ^ (s >> 16u);
    s = s + (s << 3u);
    s = s ^ (s >> 4u);
    s = s * 0x27d4eb2du;
    s = s ^ (s >> 15u);
    return s;
}

// PCG random number generator (high quality, fast)
fn pcg_random() -> u32 {
    let oldstate = rng_state;
    rng_state = oldstate * 747796405u + 2891336453u;
    let word = ((oldstate >> ((oldstate >> 28u) + 4u)) ^ oldstate) * 277803737u;
    return (word >> 22u) ^ word;
}

// Xorshift32 (corrected implementation)
fn xorshift32() -> u32 {
    var x = rng_state;
    x ^= x << 13u;
    x ^= x >> 17u;
    x ^= x << 5u;
    rng_state = x;
    return x;
}

// Main random float function [0, 1)
fn random_f32() -> f32 {
    return f32(pcg_random()) * (1.0 / 4294967296.0);
}

// Alternative using bitcast for better distribution
fn random_f32_uniform() -> f32 {
    let bits = wang_hash(rng_state);
    rng_state = xorshift32();
    let float_bits = (bits >> 9u) | 0x3f800000u; // [1.0, 2.0)
    return bitcast<f32>(float_bits) - 1.0;
}

// Random float in range [min, max)
fn rand(min: f32, max: f32) -> f32 {
    return min + random_f32_uniform() * (max - min);
}

// Box-Muller transform for normal distribution (useful for blur effects)
fn random_gaussian() -> vec2<f32> {
    let u1 = max(0.00001, random_f32()); // Avoid log(0)
    let u2 = random_f32();
    let r = sqrt(-2.0 * log(u1));
    let theta = 2.0 * 3.14159265359 * u2;
    return vec2<f32>(r * cos(theta), r * sin(theta));
}
fn vec3_rand(min: f32, max: f32) -> vec3<f32> {
    return vec3(rand(min, max), rand(min, max), rand(min, max));
}

fn set_face_normal(ray: Ray, outward_normal: vec3<f32>, r: HitRecord) -> HitRecord {
    var rec = r;
    let front_face = dot(ray.dir, outward_normal) < 0;
    rec.normal = outward_normal;
    if !front_face {
        rec.normal = -outward_normal;
    }
    return rec;
}

fn cmple(v1: vec3<f32>, v2: vec3<f32>) -> vec3<bool> {
    return vec3(v1.x <= v2.x, v1.y <= v2.y, v1.z <= v2.z);
}
fn cmple_to_unit(v1: vec3<f32>, v2: vec3<f32>) -> vec3<f32> {
    var v = vec3(0.);
    if v1.x <= v2.x {v.x = 1.;}
    if v1.y <= v2.y {v.y = 1.;}
    if v1.z <= v2.z {v.z = 1.;}
    return v;
}
// fn cmple(v1: vec3<i32>, v2: vec3<i32>) -> vec3<bool> {
//     return vec3(v1.x <= v2.x,v1.y <= v2.y,v1.z <= v2.z);
// }

fn fastFloor(v: vec3<f32>) -> vec3<i32> {
    return vec3<i32>(select(v - 1.0, v, fract(v) >= vec3<f32>(0.0)));
}fn count_bits_in_range(value: u32, start: u32, end: u32) -> u32 {
    // Create mask for the range we want (e.g., bits 1-10)
    let mask = ((1u << (end - start)) - 1u) << start;
    // Apply mask and get only the bits we want
    let masked = value & mask;
    
    // Count the bits using parallel bit counting
    var x = masked;
    x = x - ((x >> 1u) & 0x55555555u);
    x = (x & 0x33333333u) + ((x >> 2u) & 0x33333333u);
    x = (x + (x >> 4u)) & 0x0F0F0F0Fu;
    x = x + (x >> 8u);
    x = x + (x >> 16u);
    return x & 0x3Fu; // Get final count
}


struct DDAResult {
    sideDist: vec3<f32>,
    pos: vec3<i32>,
    mask: vec3<f32>,
}
fn branchless_dda(sideDist: vec3<f32>, pos: vec3<i32>, deltaDist: vec3<f32>, rayStep: vec3<i32>) -> DDAResult {
    var res = DDAResult(sideDist, pos, vec3(0.));
    if sideDist.x < sideDist.y {
        if sideDist.x < sideDist.z {
            res.sideDist.x = sideDist.x + deltaDist.x;
            res.pos.x = pos.x + rayStep.x;
            res.mask = vec3(1., 0., 0.);
        } else {
            res.sideDist.z = sideDist.z + deltaDist.z;
            res.pos.z = pos.z + rayStep.z;
            res.mask = vec3(0., 0., 1.);
        }
    } else {
        if sideDist.y < sideDist.z {
            res.sideDist.y = sideDist.y + deltaDist.y;
            res.pos.y = pos.y + rayStep.y;
            res.mask = vec3(0., 1., 0.);
        } else {
            res.sideDist.z = sideDist.z + deltaDist.z;
            res.pos.z = pos.z + rayStep.z;
            res.mask = vec3(0., 0., 1.);
        }
    }
    return res;
}

fn chunk_depth_to_size(depth: u32) -> u32 {
    return u32(pow(f32(CHUNK_SIZE), f32(depth)));
}

fn depth_to_chunk_size(depth: u32) -> u32 {
    // Convert depth to chunk size (16, 8, 4, 2, 1)
    return root_chunk_size() / chunk_depth_to_size(depth);
}

fn root_chunk_size() -> u32 {
    return chunk_depth_to_size(cam.root_max_depth);
}

fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    let cutoff = vec3<f32>(0.04045);
    let below = c / 12.92;
    let above = pow((c + 0.055) / 1.055, vec3<f32>(2.4));
    return mix(above, below, cutoff);
}

fn is_accumulating_frames() -> bool {
    return cam.accum_frames > 20;
}

struct MapDataID {
    array_array_idx: u32,
    array_idx: u32,
}

fn size_to_array_array_idx(size: u32) -> u32 {
    if size < 8 {
        return 0u;
    } else if size < 24 {
        return 1u;
    } else if size < 40 {
        return 2u;
    } else {
        return 3u;
    }
}
fn array_array_idx_to_prefix_size(array_array_idx: u32) -> u32 {
    if array_array_idx == 0u {
        return 0u;
    } else if array_array_idx == 1u {
        return 8u;
    } else if array_array_idx == 2u {
        return 24u;
    } else {
        return 40u;
    }
}
fn get_block_data(idx: MapDataID) -> MapData {
    if idx.array_array_idx == 0u {
        return block_data0[idx.array_idx];
    } else if idx.array_array_idx == 1u {
        return block_data1[idx.array_idx];
    } else if idx.array_array_idx == 2u {
        return block_data2[idx.array_idx];
    } else {
        return block_data3[idx.array_idx];
    }
    
}
fn arrayLengthBlockData(idx: u32) -> u32 {
    if idx == 0u {
        return arrayLength(&block_data0);
    } else if idx == 1u {
        return arrayLength(&block_data1);
    } else if idx == 2u {
        return arrayLength(&block_data2);
    } else {
        return arrayLength(&block_data3);
    }
}


/// Returns u32::MAX if not found
fn get_data_idx_in_chunk(chunk: VoxelChunk, _idx: u32) -> MapDataID {
    let local_idx = _idx/32u;
    let local_bit = _idx%32u;
    if (chunk.inner[local_idx] & (u32(1) << local_bit)) == 0u {
        return MapDataID(4294967295u, 4294967295u);
    }

    var ones = 0u;
    var i = 0u;
    while i < local_idx {
        ones += countOneBits(chunk.inner[i]);
        i += 1u;
    }
    
    let curr_set_bits = countOneBits(((1u << local_bit) - 1u) & chunk.inner[local_idx]);
    let chunk_idx = curr_set_bits + ones;
    let curr_array = size_to_array_array_idx(chunk_idx);
    let local_array_idx = chunk_idx - array_array_idx_to_prefix_size(curr_array);
    return MapDataID(curr_array, chunk.prefix_in_block_data_array[curr_array] + local_array_idx);
}
/// Returns u32::MAX if not found / invalid idx in tails chain or from start
/// Returns block data, not idx !
fn get_block_data_follow_tails(idx: MapDataID) -> u32 {
    var curr_idx = idx.array_idx;
    for (var i=0;i<100;i++) {
        if (curr_idx >= arrayLengthBlockData(idx.array_array_idx)) {break;}
        let curr_data = get_block_data(MapDataID(idx.array_array_idx, curr_idx)).data;
        if (curr_data&3u) == 3u { // Tail
            curr_idx = u32(curr_data >> 2);
        } else {
            return curr_data;
        }
    }
    return 4294967295u;
}


fn count_ones(n: u32) -> u32 {
    var count = 0u;
    var x = n;
    while x != 0u {
        count += x & 1u;
        x >>= 1u;
    }
    return count;
}

fn at(ray: Ray, t: f32) -> vec3<f32> {
    return ray.orig + t * ray.dir;
}

struct Camera {
    center: vec3<f32>,
    direction: vec3<f32>,
    fov: f32,
    root_max_depth: u32,
    accum_frames: u32,
    img_size: vec2<u32>,
}
struct Sphere {
    pos: vec3<f32>,
    rad: f32,
    color: vec3<f32>,
}
struct Ray {
    orig: vec3<f32>,
    dir: vec3<f32>,
}
struct VoxelChunk {
    // idx_in_parent: u32,
    inner: array<u32, CHUNK_U32_COUNT>,
    prefix_in_block_data_array: array<u32, 4>,
}
struct Voxel {
    pos: vec3<f32>,
    texture_id: u32,
}
// If t==1e30, then hit record is invalid
struct HitRecord {
    p: vec3<f32>,
    normal: vec3<f32>,
    t: f32,
    color: vec3<f32>,
}
fn valid_rec(color: vec3<f32>) -> HitRecord {
    return HitRecord(vec3(0.), vec3(0.), 0., color);
}
fn invalid_rec() -> HitRecord {
    return HitRecord(vec3(0.), vec3(0.), 1e30, vec3(0.));
}

struct MapData {
    // 2 first bits = type:
    // 00=block
    // 01=chunk
    // 10=entity
    // 11=Tail
    data: u32,
}


struct Box {
    min: vec3<f32>,
    max: vec3<f32>,
    texture_id: u32,
}


// fn local_pos(chunk: VoxelChunk) -> u32 {
//     // Returns the local position of the chunk in the world
//     return chunk.idx_in_parent;
// }
// fn ivec3_local_pos(chunk: VoxelChunk) -> vec3<i32> {
//     // Returns the local position of the chunk in the world as an ivec3
//     return vec3<i32>(vec3(chunk.idx_in_parent % 4, (chunk.idx_in_parent / 4) % 4, (chunk.idx_in_parent / 16) % 4));
// }

// No tuples

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


// @group(2) @binding(100) var<uniform> cam.img_size: vec2<f32>;


fn hit_box_gen(ray: Ray, box: Box) -> HitRecord {
    var res = invalid_rec();

    var t = hit_box_t(ray, box.min, box.max);
    if t == INVALID_BOX_HIT {
        return res; // No hit
    }
    res.t = t;
    res.p = at(ray, t);
    let center = (box.min + box.max) / 2.;
    var circle_normal = center - res.p;

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
    res.normal = circle_normal;
    res.t = t;
    // data = data%7;
    let r= data & 0xFF;
    let g= (data >> 8) & 0xFF;
    let b= (data >> 16) & 0xFF;
    let metallic = (data >> 24) & 1;
    res.color = vec3(f32(r)/255., f32(g)/255., f32(b)/255.);
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
fn hit(ray: Ray) -> HitRecord {
    var miss = invalid_rec();

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
    // Could use rcp but doesn't fix any graphical glitches
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
    var iter = 0;
    for (; iter < max_iter; iter = iter + 1) {
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
                return valid_rec(vec3(1., 0., 1.));
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
                var res = hit_box_gen(ray, Box(vec3<f32>(posi), vec3<f32>(posi) + vec3(1.0), u32(curr_data>>2)));
                // var c = vec3(1., 0., 0.);
                // break;
                // return valid_rec(c);
                return res; // making posi = 0 and rb 10000 is fun
            }
        }
        // Should be useless check but I like to keep it
        // Check if we have found something
        // if map_data_idx.array_array_idx != 4294967295u {
        //     return valid_rec(vec3(0., 1., 1.));
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
        //     return valid_rec(vec3(1., 0., 1.));
        //  }

        // nudge with scale-aware epsilon
        let eps = 1e-2 * S;
        posf += dir * (tStep + eps);
    }
    return valid_rec(vec3(0., 0., f32(iter)/500.));
    // return miss;
}
fn process_hit(ray: Ray, hit_result: HitRecord) -> HitRecord {
    var res = hit_result;
    
    // Lambertian shading - use abs or negate ray direction
    let lambert = max(0.0, dot(res.normal, ray.dir));
    res.color *= lambert;
    
    // Distance-based fog (attenuate, don't add)
    let fog_distance = 4000.0;
    let fog_factor = min(max(0.01, exp(1.-distance(cam.center, res.p) / fog_distance)), 1.);
    res.color *= fog_factor;

    
    return res;
}
// Improved ray_color with better bounce handling
fn ray_color(initial_ray: Ray) -> vec3<f32> {
    var ray = initial_ray;
    var accumulated_color = vec3(1.0);
    var final_color = vec3(0.0);
    let max_bounces = 5; // Increase for more realism
    
    for (var bounce = 0; bounce < max_bounces; bounce += 1) {
        var res = hit(ray);
        
        if res.t != 1e30 {
            // Process the hit with proper shading
            res = process_hit(ray, res);
            if !is_accumulating_frames() {
                return res.color;
            }
            
            // Material type detection (you can make this data-driven)
            let is_metallic = false; // Add material property to your hit record
            let roughness = 0.5; // Control reflection sharpness
            
            var next_direction: vec3<f32>;
            
            if is_metallic {
                // Metallic reflection
                next_direction = reflect(ray.dir, res.normal);
                // Add roughness
                next_direction += random_unit_vector() * roughness;
                next_direction = normalize(next_direction);
                
                accumulated_color *= res.color;
            } else {
                // Diffuse (Lambertian) scattering
                next_direction = res.normal + random_unit_vector();
                
                // Handle degenerate cases
                if length(next_direction) < 0.001 {
                    next_direction = res.normal;
                } else {
                    next_direction = normalize(next_direction);
                }
                
                // Energy conservation for diffuse materials
                accumulated_color *= res.color * 0.5;
            }
            
            // Prepare next ray with small offset to avoid self-intersection
            ray = Ray(res.p + next_direction * 0.001, next_direction);
            
            // Russian roulette termination for efficiency (optional)
            let survival_probability = max(accumulated_color.r, max(accumulated_color.g, accumulated_color.b));
            if rand(0., 2) > survival_probability && bounce > (max_bounces/2) {
                break;
            }
            // if min(accumulated_color.r, min(accumulated_color.g, accumulated_color.b)) < 0.01 {
            //     accumulated_color = vec3(1., 0., 0.);
            //     break;
            // }
            accumulated_color /= survival_probability;
        } else {
            // Hit skybox
            break;
        }
    }
    if all(final_color == vec3(0.)) {
        final_color = accumulated_color * skybox(ray.dir);
    }
    
    // Apply tone mapping (Reinhard is more standard than your current approach)
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
    
    rng_state = u32((((cam.accum_frames*1301348925*u32(429258578533.*sin(f32(cam.accum_frames)/100.))))&0xFF) + global_id.x + global_id.y*cam.img_size.x);
    rng_state += u32((abs(cam.center.x*10000000.+cam.center.y*1000000000.+cam.center.z*10000000.))%14982428);
    rng_state += u32((abs(cam.direction.x*100000.+cam.direction.y*1000000000.+cam.direction.z*10.))%1497428372);
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
        let depth_idx = depth_x + depth_y * (cam.img_size.x/2);
        let prev_t = max_depth[depth_idx];
        // if prev_t == 1e30 {return;}
        r.orig = at(r, prev_t);
        
        // r.orig = at(r, max_depth[global_id.x/2+global_id.y/2*(cam.img_size.x/2)]);
        c += ray_color(r) / f32(samples_per_pixel);
    }
    



    // c = vec3(rand_05_centered());
    // let texcoord = vec2(i32(global_id.x), i32(global_id.y * cam.img_size.y));
    // c = cam.direction;
    // c = vec3(0.);
    // c = vec3_rand(0, 1.);
    c *= 255.;
    var out = vec4(vec3<u32>(abs(c)), 255u);
    // out.r = u32(cam.img_size.x/100);
    // out.g = u32(cam.img_size.y/100);
    // out.b = u32(u32(cam.accum_frames));
    // var out = vec4(0, 0, 0, 255u);
    // var out = vec4(global_id, 255u);
    if max(out.r, max(out.g, out.b)) > 255u {
        let m = max(out.r, max(out.g, out.b));
        // out = out * (255u / m);
        out = vec4(1u);
    }
    out.r = min(out.r, 255u);
    out.g = min(out.g, 255u);
    out.b = min(out.b, 255u);
    out.a = min(out.a, 255u);
    let idx = global_id.x+global_id.y*(cam.img_size.x);
    let prev = accumulated_tex[idx];
    // out = u32(max_depth[idx]);
    let prev_v= vec4(prev&0xffu, (prev>>8u)&0xffu,  (prev>>16u)&0xffu,  (prev>>24u)&0xffu);
    out = (prev_v*cam.accum_frames + out) / (cam.accum_frames + 1);
    accumulated_tex[idx] = (out.r) | ((out.g) << 8u) | ((out.b) << 16u) | ((out.a) << 24u);
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