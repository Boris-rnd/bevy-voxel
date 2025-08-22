// #import bevy_sprite::{mesh2d_vertex_output::VertexOutput, mesh2d_view_bindings::globals}; 

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
    let r = abs(fract(sin(xorshift_randf32((sin(rng_seed / 3.3) * 43758.5453)))));
    rng_seed = r;
    return r;
}
fn rand(min: f32, max: f32) -> f32 {
    return min + rand_01_wang() * (max - min);
}
fn vec3_rand(min: f32, max: f32) -> vec3<f32> {
    return vec3(rand(min, max), rand(min, max), rand(min, max));
}

fn set_face_normal(ray: Ray, outward_normal: vec3<f32>, r: HitRecord) -> HitRecord {
    var rec = r;
    rec.front_face = dot(ray.dir, outward_normal) < 0;
    rec.normal = outward_normal;
    if !rec.front_face {
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

fn depth_to_chunk_size(depth: u32) -> u32 {
    // Convert depth to chunk size (16, 8, 4, 2, 1)
    return root_chunk_size() / u32(pow(4.0, f32(depth)));
}

fn root_chunk_size() -> u32 {
    return u32(pow(4.0, f32(cam.root_max_depth)));
}

/// Returns u32::MAX if not found
fn get_data_idx_in_chunk(chunk: VoxelChunk, _idx: u32) -> u32 {
    var mask = chunk.inner.x;
    var set_bits = u32(0);
    var idx = _idx;
    if idx >= 32 {
        mask = chunk.inner.y;
        idx = idx-32;
        set_bits = count_ones(chunk.inner.x) + count_ones((((1u << idx) - 1) & chunk.inner.y));
    } else {
        set_bits = count_ones((((1u << idx) - 1) & chunk.inner.x));
    }
    if (mask & (u32(1) << idx)) == 0 {
        return 4294967295u;
    }
    return set_bits+chunk.prefix_in_block_data_array;
}
/// Returns u32::MAX if not found / invalid idx in tails chain or from start
/// Returns block data, not idx !
fn get_block_data_follow_tails(idx: u32) -> u32 {
    var curr_idx = u32(idx);
    for (var i=0;i<100;i++) {
        if (curr_idx >= arrayLength(&block_data)) {break;}
        let curr_data = block_data[curr_idx].data;
        if (curr_data&3u) == 3u { // Tail
            curr_idx = u32(curr_data >> 2);
        } else {
            return curr_data;
        }
    }
    return 4294967295u;
}

fn valid_res(color: vec3<f32>) -> HitRecordResult {
    return HitRecordResult(true, HitRecord(vec3(0.), vec3(0.), 0., false, color));
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


fn local_pos(chunk: VoxelChunk) -> u32 {
    // Returns the local position of the chunk in the world
    return chunk.idx_in_parent;
}
fn ivec3_local_pos(chunk: VoxelChunk) -> vec3<i32> {
    // Returns the local position of the chunk in the world as an ivec3
    return vec3<i32>(vec3(chunk.idx_in_parent % 4, (chunk.idx_in_parent / 4) % 4, (chunk.idx_in_parent / 16) % 4));
}

// No tuples
struct HitRecordResult {
    valid: bool,
    rec: HitRecord
}

@group(0) @binding(0) var<storage, read_write> accumulated_tex: array<u32>;
@group(0) @binding(1) var<uniform> cam: Camera;
@group(0) @binding(2) var<storage, read> voxel_chunks: array<VoxelChunk>;
@group(0) @binding(3) var<storage, read> block_data: array<MapData>;
// @group(2) @binding(3) var atlas: texture_2d_array<f32>;
// @group(2) @binding(4) var base_sampler: sampler;


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
    for (var iter = 0; iter < 200; iter = iter + 1) {
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

const INVALID_BOX_HIT: f32 = 3*10e30;
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
    if data > 10 {
        res.rec.color = vec3(f32(data) / 255., 0., 0.);
    } else {
        // res.rec.color = textureSample(atlas, base_sampler, (uv) + vec2(0.5), data).xyz;
    }
    return res;
}
fn ray_color(ray2: Ray) -> vec3<f32> {
    var ray = ray2;

    let unit_direction = normalize(ray.dir);
    let a = 0.5 * (unit_direction.y + 1.0);
    var c = (1.0 - a) * vec3(1.0, 1.0, 1.0) + a * vec3(0.5, 0.7, 1.0);
    // c *= c*c*vec3(0.5, 0., 0.);

    for (var i = 1; i < 200; i += 10) {
        var res = hit(ray);
        if res.valid {
            var direction = res.rec.normal + random_unit_vector() * 0.5;
            // var direction = reflect(ray.dir, res.rec.normal) + random_unit_vector()*0.2;
            if near_zero(direction) {direction = res.rec.normal;}
            c = res.rec.color;//*(1./f32(i));

            ray = Ray(res.rec.p, direction);
            return c;
        } else {
            return c;
        }
    }
    return sqrt(c);
}

@compute @workgroup_size(1)
fn main(
    @builtin(global_invocation_id) global_id: vec3<u32>,
    @builtin(num_workgroups) grid_size: vec3<u32>,
) {
    let i = f32(global_id.x);
    let j = (1. - f32(global_id.y)/f32(grid_size.y)) * f32(grid_size.y);
    let lookfrom = cam.center;     // Point camera is looking from
    let lookat = cam.center + cam.direction;// Point camera is looking at
    let vup = vec3(0., 1., 0.); // Camera-relative "up" direction
    let defocus_angle = 5.;

    let vfov = cam.fov;

    let focal_length = 3.;
    let theta = degrees_to_radians(vfov);
    let h = tan(theta / 2);
    let viewport_height = 2. * h * focal_length;
    let viewport_width = viewport_height * (f32(grid_size.x) / f32(grid_size.y));

    let w = normalize(lookfrom - lookat);
    let u = normalize(cross(vup, w));
    let v = cross(w, u);

    let viewport_u = viewport_width * u; // Vector across viewport horizontal edge
    let viewport_v = viewport_height * (v); // Vector down viewport vertical edge
    
    // Calculate the horizontal and vertical delta vectors from pixel to pixel.
    let pixel_delta_u = viewport_u / f32(grid_size.x);
    let pixel_delta_v = viewport_v / f32(grid_size.y);

    // Calculate the location of the upper left pixel.
    let viewport_upper_left = lookfrom - focal_length * w - viewport_u / 2 - viewport_v / 2;
    let pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);


    let defocus_radius = focal_length * tan(degrees_to_radians(defocus_angle / 2));
    let defocus_disk_u = u * defocus_radius;
    let defocus_disk_v = v * defocus_radius;

    let focus = false;

    let samples_per_pixel = 1;
    var antialiasing = false;
    if samples_per_pixel > 1 {antialiasing = true;}
    var c = vec3(0.);
    // rng_seed = globals.time + (in.uv.x + in.uv.y * 10.);
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
    // let texcoord = vec2(i32(global_id.x), i32(global_id.y * grid_size.y));
    // c = ray.dir;
    c *= 255.;
    var out = vec4(vec3<u32>(c), 255u);
    // out.r = u32(cam.img_size.x/100);
    // out.g = u32(cam.img_size.y/100);
    // out.b = u32(u32(cam.accum_frames));
    // var out = vec4(0, 0, 0, 255u);
    // var out = vec4(global_id, 255u);
    out.r = min(out.r, 255u);
    out.g = min(out.g, 255u);
    out.b = min(out.b, 255u);
    out.a = min(out.a, 255u);
    accumulated_tex[global_id.x+global_id.y*grid_size.x] = (out.r) | ((out.g) << 8u) | ((out.b) << 16u) | ((out.a) << 24u);
    // out = (textureLoad(accumulated_img, texcoord) * f32(cam.accum_frames) + out) / f32(cam.accum_frames + 1);
    // textureStore(accumulated_img2, texcoord, out);
    // return out;
}