// The time since startup data is in the globals binding which is part of the mesh_view_bindings import
#import bevy_pbr::{
    mesh_view_bindings::globals,
    forward_io::VertexOutput,
}

@group(2) @binding(1) var<uniform> cam: Camera;
@group(2) @binding(2) var<storage, read> spheres: array<Sphere>;
@group(2) @binding(3) var<storage, read> boxes: array<Box>;
@group(2) @binding(6) var<storage, read> voxels: array<Voxel>;
@group(2) @binding(7) var<storage, read> voxel_chunks: array<VoxelChunk>;
@group(2) @binding(8) var<storage, read> block_data: array<MapData>;
@group(2) @binding(4) var base_color_texture: texture_2d_array<f32>;
@group(2) @binding(5) var base_color_sampler: sampler;


@group(2) @binding(100) var<uniform> img_size: vec2<f32>;


struct Camera {
    center: vec3<f32>,
    direction: vec3<f32>,
    fov: f32,
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
    idx_in_parent: u32,
    inner: vec2<u32>,
    prefix_in_block_data_array: u32,
}
struct Voxel {
    pos: vec3<f32>,
    texture_id: u32,
}
struct HitRecord {
    p: vec3<f32>,
    normal: vec3<f32>,
    t: f32,
    front_face: bool,
    color: vec3<f32>,
}


fn at(ray: Ray, t: f32) -> vec3<f32> {
    return ray.orig + t*ray.dir;
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
fn div_euclid(a: i32, b: i32) -> i32 {
    let q = a / b;
    let r = a % b;
    return q - select(0, 1, (r < 0) && (b > 0)) + select(0, 1, (r > 0) && (b < 0));
}
fn rem_euclid(a: i32, b: i32) -> i32 {
    let r = a % b;
    return select(r, r + abs(b), r < 0);
}
fn rem_euclid_v3(a: vec3<i32>, b: vec3<i32>) -> vec3<i32> {
    return vec3(rem_euclid(a.x, b.x), rem_euclid(a.y, b.y), rem_euclid(a.z, b.z));
}
fn div_euclid_v3(a: vec3<i32>, b: vec3<i32>) -> vec3<i32> {
    return vec3(div_euclid(a.x, b.x), div_euclid(a.y, b.y), div_euclid(a.z, b.z));
}
fn degrees_to_radians(deg: f32) -> f32 {
    return deg/180.*3.14159;
}

fn near_zero(v: vec3<f32>) -> bool {
    // Return true if the vector is close to zero in all dimensions.
    let s = 1e-8;
    return (abs(v.x) < s) && (abs(v.y) < s) && (abs(v.z) < s);
}
fn reflect(v: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    return v - 2.*dot(v,n)*n;
}

var<private> rng_seed: f32 = 1.;

fn random_unit_vector() -> vec3<f32> {
    for(var i=0;i<5;i++) {
        let p = vec3_rand(-1.,1.);
        let lensq = dot(p,p);
        if (1e-160 < lensq && lensq <= 1) {
            return p / sqrt(lensq);
        }
    }
    return vec3(0.);
}

fn random_on_hemisphere(normal: vec3<f32>) -> vec3<f32> {
    let on_unit_sphere = random_unit_vector();
    if (dot(on_unit_sphere, normal) > 0.0) { // In the same hemisphere as the normal
        return on_unit_sphere;
    }
    else {
        return -on_unit_sphere;
    }
}


fn random_in_unit_disk() -> vec3<f32> {
    for (var i=0;i<5;i++) {
        let p = vec3(rand(-1.,1.), rand(-1.,1.), 0.);
        if (dot(p,p) < 1.) {
            return p;

        }
    }
    return vec3(0.);
}

fn hit_sphere(sphere: Sphere, ray: Ray) -> f32 {
    let oc = sphere.pos - ray.orig;
    let a = dot(ray.dir, ray.dir);
    let b = -2.0 * dot(ray.dir, oc);
    let c = dot(oc, oc) - sphere.rad*sphere.rad;
    let discriminant = b*b - 4*a*c;
    
    if (discriminant < 0) {
        return -1.0;
    } else {
        return (-b - sqrt(discriminant) ) / (2.0*a);
    }
}

fn xorshift_rand(seed: u32) -> u32 {
    var rand = seed ^ (seed << 13);
	rand = rand >> 17;
	rand = rand << 5;
	return rand;
}
fn xorshift_randf32(seed: f32) -> f32 {
    return f32(xorshift_rand(u32(seed)));
}
fn wang_hash(u: u32) -> u32 {
    var x = u;
    x = (x ^ 61u) ^ (x >> 16u);
    x = x * 9u;
    x = x ^ (x >> 4u);
    x = x * 0x27d4eb2du;
    x = x ^ (x >> 15u);
    return x;
}

fn rand_01_wang() -> f32 {
    let u = bitcast<u32>(rng_seed);
    let h = wang_hash(u);
    let r = f32(h) / 4294967296.0; // 2^32;
    rng_seed = r;
    return r;
}

fn rand_01() -> f32 {
    let r = abs(fract(sin(xorshift_randf32((sin(rng_seed/3.3) * 43758.5453)))));
    rng_seed = r;
    return r;
}
fn rand(min: f32, max: f32) -> f32 {
    return min + rand_01_wang()*(max-min);
}
fn vec3_rand(min: f32, max: f32) -> vec3<f32> {
    return vec3(rand(min, max),rand(min, max),rand(min, max));
}

fn set_face_normal(ray: Ray, outward_normal: vec3<f32>, r: HitRecord) -> HitRecord {
    var rec = r;
    rec.front_face = dot(ray.dir, outward_normal) < 0;
    rec.normal = outward_normal;
    if (!rec.front_face) {
        rec.normal = -outward_normal;
    }
    return rec;
}

fn cmple(v1: vec3<f32>, v2: vec3<f32>) -> vec3<bool> {
    return vec3(v1.x <= v2.x,v1.y <= v2.y,v1.z <= v2.z);
}
fn cmple_to_unit(v1: vec3<f32>, v2: vec3<f32>) -> vec3<f32> {
    var v = vec3(0.);
    if v1.x<=v2.x {v.x=1.;}
    if v1.y<=v2.y {v.y=1.;}
    if v1.z<=v2.z {v.z=1.;}
    return v;
}
// fn cmple(v1: vec3<i32>, v2: vec3<i32>) -> vec3<bool> {
//     return vec3(v1.x <= v2.x,v1.y <= v2.y,v1.z <= v2.z);
// }
fn local_pos(chunk: VoxelChunk) -> u32 {
    // Returns the local position of the chunk in the world
    return chunk.idx_in_parent;
}
fn ivec3_local_pos(chunk: VoxelChunk) -> vec3<i32> {
    // Returns the local position of the chunk in the world as an ivec3
    return vec3<i32>(vec3(chunk.idx_in_parent % 4, (chunk.idx_in_parent / 4) % 4, chunk.idx_in_parent / 16));
}

// No tuples
struct HitRecordResult {
    valid: bool,
    rec: HitRecord
}

/// Returns u32::MAX if not found
// fn get_block(pos: vec3<i32>) -> u32 {
//     let block_data = get_data(pos, 20).data;
//     let ty = block_data&3;
//     if (ty == 2) { // Block
//         return block_data>>2; // Return texture id
//     } else if (ty == 1) { // Chunk
        
//     }
    
//     return u32(4294967295); // u32::MAX
// }
struct DataResult {
    data: u32,
    depth: u32,
}
/// Returns root chunk data if not found
/// max depth starts at 1
/// Returns block_data, so also has the ty in first 2 bits
fn get_data(pos: vec3<i32>, max_depth: i32) -> DataResult {
    // if pos.x==1 {return u32(1);}
    // else {return u32(4294967295);} 
    var chunk = voxel_chunks[0];
    var local_pos = vec3<i32>(0);
    var parent_pos = vec3<i32>(0);
    var depth=1;
    var curr_data = 1u; // Root chunk
    for (;depth<=max_depth;depth++) {
        parent_pos = (ivec3_local_pos(chunk)*(16 / i32(pow(4., f32(depth-1))))) + parent_pos;
        local_pos = div_euclid_v3(pos - parent_pos, vec3<i32>(16 / i32(pow(f32(4), f32(depth)))));
        var idx = u32(local_pos.x)+u32(local_pos.y)*4+u32(local_pos.z)*16;
        var mask = chunk.inner.x;
        var set_bits = u32(0);
        if idx>=32 {
            mask = chunk.inner.y;
            idx = idx-32;
            set_bits = count_bits_in_range(chunk.inner.x, 0, 32)+count_bits_in_range(chunk.inner.y, 0, idx);
        } else {
            set_bits = count_bits_in_range(chunk.inner.x, 0, idx);
        }
        if (mask&(u32(1)<<idx))==0 {
            break;
        }
        curr_data = block_data[chunk.prefix_in_block_data_array+set_bits].data;
        let ty = curr_data&3;
        if (ty == 2) { // Block
            return DataResult(curr_data, u32(depth)); // Return texture id
        } else if (ty == 1) { // Chunk
            // return set_bits; // Return texture id
            chunk = voxel_chunks[curr_data>>2];
        } else { // Error
            // return u32(4294967295); // u32::MAX
            break;
        }
        
    }
    // Returns root chunk if nothing found or latest chunk
    return DataResult(curr_data, u32(depth));
}

fn hit(ray: Ray) -> HitRecordResult {
    var temp_rec = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));
    var root_chunk = voxel_chunks[0];

    
    // Check if ray intersects the root chunk
    var t = hit_box_t(ray, vec3(0.), vec3(16.));
    if t == -1. {
        return temp_rec; // No hit
    }
    // If it does, we can start checking the chunk
    // DDA Algo
    // Saw no difference improvement on main computer, we'll see on laptop =)
    let use_branchless_dda = false;

    var rayPos = at(ray, t+0.00001);
    if all(ray.orig > vec3(0.)) && all(ray.orig < vec3(16.)) {
        rayPos = ray.orig;
    }

    var pos = vec3<i32>(rayPos);
    let deltaDist = abs(1. / ray.dir);
    var rayStep = vec3<i32>(sign(ray.dir)); 
    
    var sideDist = (sign(ray.dir) * (vec3<f32>(pos) - rayPos) + (sign(ray.dir) * 0.5) + 0.5) * deltaDist; 

    var mask = vec3(0.);

    for (var i=0;i<100;i++) {
        if any(pos < vec3(0)) || any(pos >= vec3(16)){
            break;
        }
        let _b = get_data(pos, 4);
        let block_data = _b.data;
        let depth = _b.depth;
        let ty = block_data&3;
        if ty==1 { // Chunk
            let chunk_size = 16/i32(pow(4., f32(depth+2)));
            let chunk = voxel_chunks[block_data>>2];
            // rayStep = vec3<i32>(sign(ray.dir))*vec3(1);

        }
        if (ty == 2) { // Block
            return hit_box_gen(ray, Box(vec3<f32>(pos), vec3<f32>(pos)+vec3(1.), block_data>>2));
        } 
        // else if (ty == 1) { // Chunk
        //     break;
        // }
        // let block_data = get_block(pos);
        // if block_data != 4294967295 {
        //     // We hit a block, return the hit record
        //     return hit_box_gen(ray, Box(vec3<f32>(pos), vec3<f32>(pos)+vec3(1.), block_data));
        // } else {
        //     // return hit_box_gen(ray, Box(vec3<f32>(pos), vec3<f32>(pos)+vec3(1.), 1));
        // }

        if use_branchless_dda {
            mask = cmple_to_unit(sideDist.xyz, min(sideDist.yzx, sideDist.zxy));
            sideDist += mask * deltaDist;
            pos += vec3<i32>(floor(mask)) * rayStep;
        } else {
            if (sideDist.x < sideDist.y) {
                if (sideDist.x < sideDist.z) {
                    sideDist.x += deltaDist.x;
                    pos.x += rayStep.x;
                    mask = vec3(1., 0., 0.);
                }
                else {
                    sideDist.z += deltaDist.z;
                    pos.z += rayStep.z;
                    mask = vec3(0., 0., 1.);
                }
            }
            else {
                if (sideDist.y < sideDist.z) {
                    sideDist.y += deltaDist.y;
                    pos.y += rayStep.y;
                    mask = vec3(0., 1., 0.);
                }
                else {
                    sideDist.z += deltaDist.z;
                    pos.z += rayStep.z;
                    mask = vec3(0., 0., 1.);
                }
            }
        }
    }
    
    


    // var closest_so_far = 3e38;
    // var i = u32(0);
    // while i < u32(arrayLength(&spheres)) {
    //     let r = hit_sphere_gen(ray, 0.001, closest_so_far, spheres[i]);
    //     if (r.valid) {
    //         temp_rec = r;
    //         closest_so_far = r.rec.t;
    //     }
    //     i++;
    // }
    // i = 0;
    // while i < u32(arrayLength(&boxes)) {
    //     let r = hit_box_gen(ray, boxes[i]);
    //     if (r.valid && r.rec.t < closest_so_far && r.rec.t > 0.001) {
    //         temp_rec = r;
    //         closest_so_far = r.rec.t;
    //     }
    //     i++;
    // }
    // i = 0;
    // while i < u32(arrayLength(&voxel_chunks)) {
    //     let r = hit_chunk_gen(ray, voxel_chunks[i]);
    //     if (r.valid && r.rec.t < closest_so_far && r.rec.t > 0.001) {
    //         temp_rec = r;
    //         closest_so_far = r.rec.t;
    //     }
    //     i++;
    // }
    return temp_rec;
}

fn hit_box_t(ray: Ray, bmin: vec3<f32>, bmax: vec3<f32>) -> f32 {
    let t135 = (bmax-ray.orig)/ray.dir;
    let t246 = (bmin-ray.orig)/ray.dir;

    let tmin = max(max(min(t135.x, t246.x), min(t135.y, t246.y)), min(t135.z, t246.z));
    let tmax = min(min(max(t135.x, t246.x), max(t135.y, t246.y)), max(t135.z, t246.z));

    if (tmin > tmax || tmax < 0) {
        return -1.0;
    }
    return tmin;
}

fn hit_box_gen(ray: Ray, box: Box) -> HitRecordResult {
    var res = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));

    var t = hit_box_t(ray, box.min, box.max);
    if t==-1.0 {
        return res; // No hit
    }
    res.valid = true;
    res.rec.p = at(ray, t);
    let center = (box.min+box.max)/2.;
    var circle_normal = center-res.rec.p;
    
    var uv: vec2<f32>;
    var data: u32 = box.texture_id;
    if circle_normal.x > abs(circle_normal.y) && circle_normal.x > abs(circle_normal.z) {
        uv = (circle_normal).zy;
        circle_normal = vec3(1., 0., 0.);
    }
    else if circle_normal.x < -abs(circle_normal.y) && circle_normal.x < -abs(circle_normal.z) {
        uv = (circle_normal).zy;
        circle_normal = vec3(-1., 0., 0.);
    }
    
    else if circle_normal.z > abs(circle_normal.y) && circle_normal.z > abs(circle_normal.x) {
        uv = (circle_normal).xy;
        circle_normal = vec3(0., 0., 1.);
    }
    else if circle_normal.z < -abs(circle_normal.y) && circle_normal.z < -abs(circle_normal.x) {
        uv = (circle_normal).xy;
        circle_normal = vec3(0., 0., -1.);
    }
    
    else if circle_normal.y > abs(circle_normal.x) && circle_normal.y > abs(circle_normal.z) {
        uv = (circle_normal).xz;
        circle_normal = vec3(0., 1., 0.);
        // data = 1;
    }
    else if circle_normal.y < -abs(circle_normal.x) && circle_normal.y < -abs(circle_normal.z) {
        uv = (circle_normal).xz;
        circle_normal = vec3(0., -1., 0.);
        // data = 1;
    }
    else {
        circle_normal = vec3(1., 1.5, 1.);
    }
    res.rec.normal = circle_normal;
    res.rec.t = t;
    res.rec.front_face = false;
    res.rec.color = textureSample(base_color_texture, base_color_sampler, (uv)+vec2(0.5), data).xyz;
    return res;
}
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
fn get_block_data(chunk: VoxelChunk, target_idx: u32) -> u32 {
    var current_idx = chunk.prefix_in_block_data_array;
    var found_count = 0u;
    
    while (found_count < target_idx) {
        let current = block_data[current_idx];
        // Check if it's a tail (type bits = 11)
        if ((current.data & 3) == 3) {
            current_idx = current.data >> 2u; // Get next index
            found_count += 1u;
        } else {
            break; // Corrupted list
        }
    }
    return current_idx;
}

// fn hit_chunk_gen(ray: Ray, chunk: VoxelChunk) -> HitRecordResult {
//     // Calculate chunk bounds
//     let chunk_min = vec3<f32>(chunk.pos * 4);
//     let chunk_max = chunk_min + vec3(4.0);
//     let box = Box(chunk_min, chunk_max, 0);

//     // Ray-box intersection test for chunk bounds
//     let t135 = (box.max - ray.orig) / ray.dir;
//     let t246 = (box.min - ray.orig) / ray.dir;
    
//     let tmin = max(max(min(t135.x, t246.x), min(t135.y, t246.y)), min(t135.z, t246.z));
//     let tmax = min(min(max(t135.x, t246.x), max(t135.y, t246.y)), max(t135.z, t246.z));
    
//     var res = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));
//     if (tmin > tmax || tmax < 0.0) {
//         return res;
//     }
//     // Saw no difference improvement on main computer, we'll see on laptop =)
//     let use_branchless_dda = true;
    
//     let rayPos = at(ray, tmin+0.00001)-box.min;
//     var pos = vec3<i32>(rayPos);
//     let deltaDist = abs(1. / ray.dir);
//     let rayStep = vec3<i32>(sign(ray.dir)); 
    
//     var sideDist = (sign(ray.dir) * (vec3<f32>(pos) - rayPos) + (sign(ray.dir) * 0.5) + 0.5) * deltaDist; 

//     var mask = vec3(0.);

//     for (var i=0;i<16;i++) {
//         if any(pos < vec3(0)) || any(pos >= vec3(4)){
//             break;
//         }
//         var real_box = Box(vec3<f32>(pos)+box.min,vec3<f32>(pos)+box.min+vec3(1.), 0);
        
//         var idx = u32(pos.x)+u32(pos.y)*4+u32(pos.z)*16;
//         var bitmask: u32;
//         if (idx<32) {
//             bitmask = chunk.inner.x;
//         } else {
//             bitmask = chunk.inner.y;
//             idx = idx-32;
//         }
//         if (((bitmask >> idx) & 1) == 1) {
//             let block_data = block_data[get_block_data(chunk, idx)];

//             real_box.texture_id = block_data.data;
//             return hit_box_gen(ray, real_box);
//         }
//         if use_branchless_dda {
//             mask = cmple_to_unit(sideDist.xyz, min(sideDist.yzx, sideDist.zxy));
//             sideDist += mask * deltaDist;
//             pos += vec3<i32>(floor(mask)) * rayStep;
//         } else {
//             if (sideDist.x < sideDist.y) {
//                 if (sideDist.x < sideDist.z) {
//                     sideDist.x += deltaDist.x;
//                     pos.x += rayStep.x;
//                     mask = vec3(1., 0., 0.);
//                 }
//                 else {
//                     sideDist.z += deltaDist.z;
//                     pos.z += rayStep.z;
//                     mask = vec3(0., 0., 1.);
//                 }
//             }
//             else {
//                 if (sideDist.y < sideDist.z) {
//                     sideDist.y += deltaDist.y;
//                     pos.y += rayStep.y;
//                     mask = vec3(0., 1., 0.);
//                 }
//                 else {
//                     sideDist.z += deltaDist.z;
//                     pos.z += rayStep.z;
//                     mask = vec3(0., 0., 1.);
//                 }
//             }
//         }
//     }
//     return res;
// }

// fn box_hit(ray: Ray, idx2: u32, chunk: VoxelChunk, box: Box, t: f32) -> HitRecordResult {
//     var res = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));
    
//     var idx = idx2;
//     var mask: u32;
//     if (idx<32) {
//         mask = chunk.inner.x;
//     } else {
//         mask = chunk.inner.y;
//         idx = idx-32;
//     }
//     let m = (mask >> idx) & u32(1);
//     if (m==1) {
//         return hit_box_gen(ray, box);
//     }
//     return res;
// }
// fn box_hit(ray: Ray, idx2: u32, chunk: VoxelChunk, box: Box, t: f32) -> HitRecordResult {
//     var res = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));
    
//     var idx = idx2;
//     var mask: u32;
//     if (idx < 32u) {
//         // Debug: Return red for first 32 bits
//         if (chunk.inner.x != 0u) {
//             return HitRecordResult(true, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(1.0, 0.0, 0.0)));
//         }
//     } else {
//         // Debug: Return blue for last 32 bits
//         if (chunk.inner.y != 0u) {
//             return HitRecordResult(true, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.0, 0.0, 1.0)));
//         }
//         idx = idx - 32u;
//     }

//     // Original logic
//     let m = (mask >> idx) & u32(1);
//     if (m == 1u) {
//         return hit_box_gen(ray, box);
//     }
//     return res;
// }

// fn box_hit(ray: Ray, pos: vec3<f32>, chunk: VoxelChunk, box: Box, t: f32) -> HitRecordResult {
//     var res = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));
    
    
//     return res;
// }


fn hit_sphere_gen(ray: Ray, ray_tmin: f32, ray_tmax: f32, sphere: Sphere) -> HitRecordResult {
    var res = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));

    let oc = sphere.pos - ray.orig;
    let a = dot(ray.dir,ray.dir);
    let h = dot(ray.dir, oc);
    let c = dot(oc,oc) - sphere.rad*sphere.rad;

    let discriminant = h*h - a*c;
    if (discriminant < 0.) {
        return res;
    }

    let sqrtd = sqrt(discriminant);

    // // Find the nearest root that lies in the acceptable range.
    let root = (h - sqrtd) / a;
    if (root <= ray_tmin || ray_tmax <= root) {
        let root = (h + sqrtd) / a;
        if (root <= ray_tmin || ray_tmax <= root) {return res;}
    }
    
    res.valid = true;
    res.rec.t = root;
    res.rec.p = at(ray, res.rec.t);
    // res.rec = set_face_normal(ray, outward_normal, res.rec);
    res.rec.normal = (res.rec.p - sphere.pos) / sphere.rad;
    if (!(dot(ray.dir, res.rec.normal) < 0)) {
        res.rec.normal = -res.rec.normal;
    }
    res.rec.color = sphere.color;
    
    return res;
}

fn ray_color(ray2: Ray) -> vec3<f32> {
    var ray = ray2;
    
    let unit_direction = normalize(ray.dir);
    let a = 0.5*(unit_direction.y + 1.0);
    var c = (1.0-a)*vec3(1.0, 1.0, 1.0) + a*vec3(0.5, 0.7, 1.0);

    for (var i =1;i<200;i+=10) {
        var res = hit(ray);
        if (res.valid) {
            var direction = res.rec.normal + random_unit_vector()*0.5;
            // var direction = reflect(ray.dir, res.rec.normal) + random_unit_vector()*0.2;
            if (near_zero(direction)){direction = res.rec.normal;}
            c = c*res.rec.color;//*(1./f32(i));
            
            ray = Ray(res.rec.p, direction);
            return c;
        } else {
            return c;
        }
    }
    return sqrt(c);
}
@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let lookfrom = cam.center;     // Point camera is looking from
    let lookat   = cam.center+cam.direction;// Point camera is looking at
    let vup      = vec3(0.,1.,0.); // Camera-relative "up" direction
    let defocus_angle = 5.;

    let vfov = cam.fov;
    
    let focal_length = 3.;
    let theta = degrees_to_radians(vfov);
    let h = tan(theta/2);
    let viewport_height = 2. * h * focal_length;
    let viewport_width = viewport_height * (img_size.x/img_size.y);

    let w = normalize(lookfrom - lookat);
    let u = normalize(cross(vup, w));
    let v = cross(w, u);
    
    let viewport_u = viewport_width*u; // Vector across viewport horizontal edge
    let viewport_v = viewport_height*(-v); // Vector down viewport vertical edge
    
    // Calculate the horizontal and vertical delta vectors from pixel to pixel.
    let pixel_delta_u = viewport_u / img_size.x;
    let pixel_delta_v = viewport_v / img_size.y;

    // Calculate the location of the upper left pixel.
    let viewport_upper_left = lookfrom - focal_length*w - viewport_u/2 - viewport_v/2;
    let pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);
    
    let i = in.uv.x * img_size.x;
    let j = (1.-in.uv.y) * img_size.y;

    let defocus_radius = focal_length * tan(degrees_to_radians(defocus_angle / 2));
    let defocus_disk_u = u * defocus_radius;
    let defocus_disk_v = v * defocus_radius;

    let focus = false;
    
    let samples_per_pixel = 1;
    var antialiasing = false;
    if samples_per_pixel>1 {antialiasing=true;}
    var c = vec3(0.);
    rng_seed = globals.time+(in.uv.x+in.uv.y*10.);
    for (var s=0;s<samples_per_pixel;s++) {
        var offset = vec3(0.);
        if samples_per_pixel>1 {
            let offset_x = rand(-0.5, 0.5);
            let offset_y = rand(-0.5, 0.5);
            offset = vec3(offset_x, offset_y, 0.);
        }
        let pixel_center = pixel00_loc + ((i+offset.x) * pixel_delta_u) + ((j+offset.y) * pixel_delta_v);
        var orig = lookfrom;
        if (focus) {
            let p = random_in_unit_disk();
            orig += (p.x * defocus_disk_u) + (p.y * defocus_disk_v);
        }
        let r = Ray(orig, pixel_center-lookfrom);
        c += ray_color(r)/f32(samples_per_pixel);
    }
    



    // c = vec3(rand_05_centered());
    return vec4<f32>(c, 1.0);
}