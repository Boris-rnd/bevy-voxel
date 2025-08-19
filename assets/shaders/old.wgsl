
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


// fn hit_sphere_gen(ray: Ray, ray_tmin: f32, ray_tmax: f32, sphere: Sphere) -> HitRecordResult {
//     var res = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));

//     let oc = sphere.pos - ray.orig;
//     let a = dot(ray.dir,ray.dir);
//     let h = dot(ray.dir, oc);
//     let c = dot(oc,oc) - sphere.rad*sphere.rad;

//     let discriminant = h*h - a*c;
//     if (discriminant < 0.) {
//         return res;
//     }

//     let sqrtd = sqrt(discriminant);

//     // // Find the nearest root that lies in the acceptable range.
//     let root = (h - sqrtd) / a;
//     if (root <= ray_tmin || ray_tmax <= root) {
//         let root = (h + sqrtd) / a;
//         if (root <= ray_tmin || ray_tmax <= root) {return res;}
//     }
    
//     res.valid = true;
//     res.rec.t = root;
//     res.rec.p = at(ray, res.rec.t);
//     // res.rec = set_face_normal(ray, outward_normal, res.rec);
//     res.rec.normal = (res.rec.p - sphere.pos) / sphere.rad;
//     if (!(dot(ray.dir, res.rec.normal) < 0)) {
//         res.rec.normal = -res.rec.normal;
//     }
//     res.rec.color = sphere.color;
    
//     return res;
// }


// fn hit() {


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
    // return temp_rec;}



    
// fn hit_sphere(sphere: Sphere, ray: Ray) -> f32 {
//     let oc = sphere.pos - ray.orig;
//     let a = dot(ray.dir, ray.dir);
//     let b = -2.0 * dot(ray.dir, oc);
//     let c = dot(oc, oc) - sphere.rad*sphere.rad;
//     let discriminant = b*b - 4*a*c;
    
//     if (discriminant < 0) {
//         return -1.0;
//     } else {
//         return (-b - sqrt(discriminant) ) / (2.0*a);
//     }
// }
// fn get_block_data(chunk: VoxelChunk, target_idx: u32) -> u32 {
//     var current_idx = chunk.prefix_in_block_data_array;
//     var found_count = 0u;
    
//     while (found_count < target_idx) {
//         let current = block_data[current_idx];
//         // Check if it's a tail (type bits = 11)
//         if ((current.data & 3) == 3) {
//             current_idx = current.data >> 2u; // Get next index
//             found_count += 1u;
//         } else {
//             break; // Corrupted list
//         }
//     }
//     return current_idx;
// }
