// The time since startup data is in the globals binding which is part of the mesh_view_bindings import
// import bevy_pbr::mesh_view_bindings::globals;
#import bevy_pbr::{forward_io::VertexOutput, mesh_view_bindings::globals};

include! assets/shaders/utils.wgsl


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
    root_chunk_size: u32,
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

struct DataResult {
    data: u32,
    depth: u32,
}
/// Returns root chunk data if not found
/// max depth starts at 1
/// Returns block_data, so also has the ty in first 2 bits
fn get_data_in_chunk(pos: vec3<i32>, chk: VoxelChunk, par_pos: vec3<i32>, dep:u32, max_depth: u32) -> DataResult {
    // if pos.x==1 {return u32(1);}
    // else {return u32(4294967295);} 
    var chunk = chk;
    var local_pos = vec3<i32>(0);
    var parent_pos = par_pos;
    var end_depth = dep;
    var curr_data = 1u; // Root chunk
    for (var depth = dep;depth<=max_depth;depth++) {
        end_depth = depth;
        let chunk_size = i32(depth_to_chunk_size(depth-1));
        parent_pos += (ivec3_local_pos(chunk)*chunk_size);
        local_pos = div_euclid_v3(pos - parent_pos, vec3<i32>(chunk_size/4));
        var idx = u32(local_pos.x)+u32(local_pos.y)*4+u32(local_pos.z)*16;
        var mask = chunk.inner.x;
        var set_bits = u32(0);
        if idx>=64 && depth==3 {return DataResult(0, 0);}
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
    return DataResult(curr_data, u32(end_depth));
}

fn hit(ray: Ray) -> HitRecordResult {
    var temp_rec = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));
    var root_chunk = voxel_chunks[0];

    
    // Check if ray intersects the root chunk
    var t = hit_box_t(ray, vec3(0.), vec3(f32(root_chunk_size())));
    if t == -1. {
        return temp_rec; // No hit
    }
    // If it does, we can start checking the chunk
    // DDA Algo
    // Saw no difference improvement on main computer, we'll see on laptop =)
    let use_branchless_dda = false;

    var rayPos = at(ray, t+0.00001);
    if all(ray.orig > vec3(0.)) && all(ray.orig < vec3(f32(root_chunk_size()))) {
        rayPos = ray.orig;
    }

    var pos = vec3<i32>(rayPos);
    var deltaDist = abs(1. / ray.dir);
    var rayStep = vec3<i32>(sign(ray.dir)); 
    
    var sideDist = (sign(ray.dir) * (vec3<f32>(pos) - rayPos) + (sign(ray.dir) * 0.5) + 0.5) * deltaDist; 

    var mask = vec3(0.);

    var curr_chunk = root_chunk;
    var parent_pos = vec3<i32>(0);
    var depth = 1u;
    var step_size = 1;

    for (var i=0;i<200;i++) {
        if any(pos < vec3(0)) || any(pos >= vec3(i32(root_chunk_size()))){
            break;
        }
        let _b = get_data_in_chunk(pos, curr_chunk,parent_pos, depth, 6);
        if _b.data==0 && _b.depth==0 {
            break; // No data found, stop
        }
        let block_data = _b.data;
        let ty = block_data&3u;
        if ty==1u { // Chunk is not empty, so traverse it to know if we hit something
            // depth = _b.depth;
            // var S      = 1; 
            step_size = i32(depth_to_chunk_size(_b.depth));
            // pos = div_euclid_v3(pos, vec3<i32>(step_size)) * step_size;
//             let S = i32(depth_to_chunk_size(depth));   // chunk size in voxels
// let sgn = sign(ray.dir);

// // align position to chunk grid
// let base = div_euclid_v3(pos, vec3<i32>(S)) * S;
// pos = base;

// // distance to next boundary in each axis
// let next_boundary = base + select(vec3<i32>(0), vec3<i32>(S), sgn > vec3(0.));
// sideDist = (vec3<f32>(next_boundary) - rayPos) / ray.dir;

// // stride + step
// deltaDist = abs(vec3<f32>(S) / ray.dir);
// rayStep   = vec3<i32>(sgn) * S;
            // let sgn    = sign(ray.dir);
            // let invDir = abs(1.0 / ray.dir);

            // // align current voxel to this chunk cell
            // pos = div_euclid_v3(pos, vec3<i32>(S)) * S;

            // // rescale DDA
            // deltaDist = abs(vec3<f32>(S) / ray.dir);
            // sideDist  = ( sgn * (vec3<f32>(pos) - rayPos)
            //             + sgn * (0.5 * f32(S)) + 0.5 * f32(S) ) * invDir;

            // rayStep   = vec3<i32>(sgn) * S;

        }
        if (ty == 2u) { // Block
            return hit_box_gen(ray, Box(vec3<f32>(pos), vec3<f32>(pos)+vec3(1.), block_data>>2)); // block_data>>2 | u32(i)
        } 

        for (var j=0;j<step_size;j++) {
            if use_branchless_dda {
                mask = cmple_to_unit(sideDist.xyz, min(sideDist.yzx, sideDist.zxy));
                sideDist += mask * deltaDist;
                pos += vec3<i32>(floor(mask)) * rayStep;
            } else {
                let _vals = branchless_dda(sideDist, pos, deltaDist, rayStep);
                sideDist = _vals.sideDist;
                pos = _vals.pos;
                mask = _vals.mask;
            }

        }
    }
    return temp_rec; // No hit
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
    if data>10 {
        res.rec.color = vec3(f32(data)/255., 0., 0.);
    } else {
        res.rec.color = textureSample(base_color_texture, base_color_sampler, (uv)+vec2(0.5), data).xyz;
    }
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
    
    let samples_per_pixel = 2;
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