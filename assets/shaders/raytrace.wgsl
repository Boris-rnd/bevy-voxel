// The time since startup data is in the globals binding which is part of the mesh_view_bindings import
#import bevy_pbr::{
    mesh_view_bindings::globals,
    forward_io::VertexOutput,
}

@group(2) @binding(1) var<uniform> cam: Camera;
@group(2) @binding(2) var<storage, read> spheres: array<Sphere>;
@group(2) @binding(3) var<storage, read> boxes: array<Box>;
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


struct Box {
    min: vec3<f32>,
    max: vec3<f32>,
    color: vec3<f32>,
}

fn degrees_to_radians(deg: f32) -> f32 {
    return deg/180.*3.14159;
}

// fn intersection(b: Box, r: Ray) {
//     let tx1 = (b.min.x - r.orig.x)*r.dir.x;
//     let tx2 = (b.max.x - r.orig.x)*r.dir.x;

//     var tmin = min(tx1, tx2);
//     var tmax = max(tx1, tx2);

//     let ty1 = (b.min.y - r.orig.y)*r.dir.y;
//     let ty2 = (b.max.y - r.orig.y)*r.dir.y;

//     tmin = max(tmin, min(ty1, ty2));
//     tmax = min(tmax, max(ty1, ty2));

//     return tmax >= tmin;
// }

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


// No tuples
struct HitRecordResult {
    valid: bool,
    rec: HitRecord
}

fn hit(ray: Ray) -> HitRecordResult {
    var temp_rec = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));
    var closest_so_far = 3e38;
    var i = u32(0);
    while i < u32(arrayLength(&spheres)) {
        let r = hit_sphere_gen(ray, 0.001, closest_so_far, spheres[i]);
        if (r.valid) {
            temp_rec = r;
            closest_so_far = r.rec.t;
        }
        i++;
    }
    i = 0;
    while i < u32(arrayLength(&boxes)) {
        let r = hit_box_gen(ray, boxes[i]);
        if (r.valid && r.rec.t < closest_so_far && r.rec.t > 0.001) {
            temp_rec = r;
            closest_so_far = r.rec.t;
        }
        i++;
    }
    return temp_rec;
}

fn hit_box_gen(ray: Ray, box: Box) -> HitRecordResult {
    let rt = box.min;
    let lb = box.max;

    let t135 = (lb-ray.orig)/ray.dir;
    let t246 = (rt-ray.orig)/ray.dir;

    let tmin = max(max(min(t135.x, t246.x), min(t135.y, t246.y)), min(t135.z, t246.z));
    let tmax = min(min(max(t135.x, t246.x), max(t135.y, t246.y)), max(t135.z, t246.z));
    
    var res = HitRecordResult(false, HitRecord(vec3(0.), vec3(0.), 0., false, vec3(0.)));

    var t: f32;
    // if tmax < 0, ray (line) is intersecting AABB, but the whole AABB is behind us
    // if (tmax < 0) {
    //     t = tmax;
    //     c = vec3(1., 0., 0.);
    // }
    // if tmin > tmax, ray doesn't intersect AABB
    if (tmin > tmax || tmax<0) {
        t = tmax;
    } else {
        t = tmin;
        res.valid = true;
        res.rec.p = at(ray, t);
        let center = (box.min+box.max)/2.;
        var circle_normal = center-res.rec.p;
        
        var uv: vec2<f32>;
        var layer: u32;
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
            layer = 1;
        }
        else if circle_normal.y < -abs(circle_normal.x) && circle_normal.y < -abs(circle_normal.z) {
            uv = (circle_normal).xz;
            circle_normal = vec3(0., -1., 0.);
            layer = 1;
        }
        else {
            circle_normal = vec3(1., 1.5, 1.);
        }
        res.rec.normal = circle_normal;
        res.rec.t = t;
        res.rec.front_face = false;
        res.rec.color = textureSample(base_color_texture, base_color_sampler, (uv)+vec2(0.5), layer).xyz;
    }
    return res;
}

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

    for (var i =1;i<300;i+=10) {
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
    
    let samples_per_pixel = 3;
    var c = vec3(0.);
    rng_seed = globals.time+(in.uv.x+in.uv.y*10.);
    for (var s=0;s<samples_per_pixel;s++) {
        let offset_x = rand(-0.5, 0.5);
        let offset_y = rand(-0.5, 0.5);
        let offset = vec3(offset_x, offset_y, 0.);
        let pixel_center = pixel00_loc + ((i+offset_x) * pixel_delta_u) + ((j+offset_y) * pixel_delta_v);
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