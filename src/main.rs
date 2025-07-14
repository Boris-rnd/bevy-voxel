#![allow(unused_imports, dead_code)]
pub static mut CUBE_COUNT: usize = 0;
use std::ops::RangeInclusive;

use bevy::{pbr::{NotShadowCaster, NotShadowReceiver}, prelude::*, render::{batching::NoAutomaticBatching, view::NoFrustumCulling}};
use camera::PanOrbitCameraBundle;
use noise::{NoiseFn, Perlin};
use world::{CHUNK_SIZE, CHUNK_SIZEI};

pub mod camera;
pub mod build;
pub mod world;

fn main() {
    let mut app = App::new();
    app.add_plugins(DefaultPlugins)
    //    .add_plugins(MeshletPlugin)
       .add_plugins(bevy::diagnostic::FrameTimeDiagnosticsPlugin::default())
       .add_plugins(iyes_perf_ui::PerfUiPlugin)
       .add_plugins(world::WorldPlugin{})
       .add_systems(Startup, setup)
       .add_systems(Startup, build::setup)
       .add_systems(Update, build::build)
       .add_systems(Update, camera::camera_movement);

    // #[cfg(debug_assertions)] // debug/dev builds only
    // app.add_plugins(bevy::diagnostic::LogDiagnosticsPlugin {
    //     debug: true,
    //     wait_duration: Duration::from_secs(1),
    //     filter: Some(vec![DiagnosticPath::new()]),
    // });

    app.run();
}

pub fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    // mut meshes_let: ResMut<Assets<MeshletMesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    commands.spawn(iyes_perf_ui::prelude::PerfUiCompleteBundle::default());
    let mut camera = PanOrbitCameraBundle {
        camera: Camera3dBundle { ..Default::default() },
        ..Default::default()
    };
    // Position our camera using our component,
    // not Transform (it would get overwritten)
    camera.state.center = Vec3::new(0.0, 10.0, 0.0);
    camera.state.radius = 50.0;
    camera.state.pitch = 0.0f32.to_radians();
    camera.state.yaw = 90.0f32.to_radians();
    commands.spawn(camera);
    // .insert(GpuCulling).insert(NoCpuCulling);
    let world = world::World::new(0);
    let material = materials.add(Color::srgb_u8(255, 255, 255));
    let cube = meshes.add(Cuboid::new(1., 1., 1.));

    for x in -2..2 {
        for z in -2..2 {
            gen_chunk(x, z, &world, &mut commands, cube.clone(), material.clone());
        }
    }
    dbg!(unsafe{CUBE_COUNT});

    commands.spawn(MaterialMeshBundle {
        mesh: meshes.add(Cuboid::new(1., 1., 1.)),
        material: materials.add(Color::srgb_u8(0, 255, 0)),
        transform: Transform::from_xyz(0., 0., 1.),
        ..default()
    });
    commands.spawn(MaterialMeshBundle {
        mesh: meshes.add(Cuboid::new(1., 1., 1.)),
        material: materials.add(Color::srgb_u8(255, 0, 0)),
        transform: Transform::from_xyz(0., 1., 0.),
        ..default()
    });
    commands.spawn(MaterialMeshBundle {
        mesh: meshes.add(Cuboid::new(1., 1., 1.)),
        material: materials.add(Color::srgb_u8(0, 0, 255)),
        transform: Transform::from_xyz(1., 0., 0.),
        ..default()
    });
    // commands.spawn(PointLightBundle {
    //     transform: Transform::from_xyz(0., 500., 0.),
    //     point_light: PointLight { color: Color::WHITE, intensity: 100000., range: 20000., radius: 10000., shadows_enabled: true, ..Default::default() },
    //     ..Default::default()
    // });
}
fn add_cube(commands: &mut Commands, mesh: Handle<Mesh>, material: Handle<StandardMaterial>, transform: Transform) {
    unsafe { CUBE_COUNT += 1 };
    commands.spawn(MaterialMeshBundle {
        mesh,
        material,
        transform,
        ..Default::default()
    })
    // commands.spawn(MaterialMeshletMeshBundle {
    //     meshlet_mesh: mesh,
    //     material,
    //     transform,
    //     ..Default::default()
    // })
    .insert((NotShadowCaster, NotShadowReceiver, ));

}
fn add_cubes_y(commands: &mut Commands, mesh: Handle<Mesh>, material: Handle<StandardMaterial>, x: f32, z: f32, y_bounds: RangeInclusive<i32>) {
    let mut transform = Transform::from_translation(Vec3::new(x,*y_bounds.start() as f32,z));
    transform.scale.y = ((y_bounds.end()+1) - y_bounds.start()) as f32;
    transform.translation.y += transform.scale.y/2. -0.5;
    add_cube(commands, mesh.clone(), material.clone(), transform);
    // for y in y_bounds {
    //     add_cube(commands, mesh.clone(), material.clone(), Transform::from_translation(Vec3::new(x,y as f32,z)));
    // }
}

fn gen_chunk(base_x: i32, base_z: i32, world: &world::World, commands: &mut Commands, mesh: Handle<Mesh>, material: Handle<StandardMaterial>,) {
    let mut heights = [0i32; CHUNK_SIZE*CHUNK_SIZE];
    for x in 0..CHUNK_SIZE {
        for z in 0..CHUNK_SIZE {
            heights[x*CHUNK_SIZE+z] = world.get_height_at(x as i32+base_x, z as i32+base_z);
        }
    }
    for x in 0..CHUNK_SIZE {
        for z in 0..CHUNK_SIZE {
            let current = x*CHUNK_SIZE+z;
            let iy = heights[current];
            let fx = (x as i32+base_x) as f32;
            let fy = iy as f32;
            let fz = (z as i32+base_z) as f32;
            let ix = fx as i32;
            let iz = fz as i32;
            if z > 0 {
                add_cubes_y(commands, mesh.clone(), material.clone(), fx, fz-1., if iy > heights[current-1] {
                    heights[current-1]..=iy
                } else if iy < heights[current-1] {
                    iy+1..=heights[current-1]
                } else {iy..=iy});
            }
            if z < CHUNK_SIZE-1 {
                add_cubes_y(commands, mesh.clone(), material.clone(), fx, fz+1., if iy > heights[current+1] {
                    heights[current+1]..=iy
                } else if iy < heights[current+1] {
                    iy+1..=heights[current+1]
                } else {iy..=iy});
            }
            if x > 0 {
                add_cubes_y(commands, mesh.clone(), material.clone(), fx-1., fz, if iy > heights[current-CHUNK_SIZE] {
                    heights[current-CHUNK_SIZE]..=iy
                } else if iy < heights[current-CHUNK_SIZE] {
                    iy+1..=heights[current-CHUNK_SIZE]
                } else {iy..=iy});
            }
            if x < CHUNK_SIZE-1 {
                add_cubes_y(commands, mesh.clone(), material.clone(), fx+1., fz, if iy > heights[current+CHUNK_SIZE] {
                    heights[current+CHUNK_SIZE]..=iy
                } else if iy < heights[current+CHUNK_SIZE] {
                    iy+1..=heights[current+CHUNK_SIZE]
                } else {iy..=iy});
            }
        }
    }
}


#[derive(Component)]
pub struct Chunk;



// let mut positions = Vec::new();
// let mut indices = Vec::new();
// let mut normals = Vec::new();
// let mut id = 0;
// for x in 0..16 {
//     for z in 0..16 {
//         let bx = x as f32;
//         let by = heights[id];
//         let bz = z as f32;
//         positions.append(&mut vec![
//             [bx, by, bz],
//             [bx+1., by, bz],
//             [bx+1., by, bz+1.],
//             [bx, by, bz+1.],
//         ]);
//         let vid = id as u16*4;
//         // Top corner
//         indices.append(&mut vec![
//             vid+0, vid+1, vid+2, 
//             vid+0, vid+2, vid+3,
//         ]);
//         normals.append(&mut vec![
//             [0., 1., 0.],
//             [0., 1., 0.],
//             [0., 1., 0.],
//             [0., 1., 0.],
//         ]);
//         // Check neighboring blocks and generate additional faces
//         if bx > 0. && heights[id-16] < by { // Left face (x-1)
//             indices.append(&mut vec![
//                 vid-16*4, vid-16*4+3, vid+0,
//                 vid-16*4+3, vid+3, vid+0,
//             ]);
//             normals.append(&mut vec![
//                 [-1., 0., 0.],
//                 [-1., 0., 0.],
//                 [-1., 0., 0.],
//                 [-1., 0., 0.],
//             ]);
//         }
//         if bx < 15. && heights[id+16] < by { // Right face (x+1)
//             indices.append(&mut vec![
//                 vid+1, vid+2, vid+16*4+1,
//                 vid+2, vid+16*4+2, vid+16*4+1,
//             ]);
//             normals.append(&mut vec![
//                 [1., 0., 0.],
//                 [1., 0., 0.],
//                 [1., 0., 0.],
//                 [1., 0., 0.],
//             ]);
//         }
//         if bz > 0. && heights[id-1] < by { // Front face (z-1)
//             indices.append(&mut vec![
//                 vid-1*4+3, vid-1*4+2, vid+0,
//                 vid-1*4+2, vid+1, vid+0,
//             ]);
//             normals.append(&mut vec![
//                 [0., 0., -1.],
//                 [0., 0., -1.],
//                 [0., 0., -1.],
//                 [0., 0., -1.],
//             ]);
//         }
//         if bz < 15. && heights[id+1] < by { // Back face (z+1)
//             indices.append(&mut vec![
//                 vid+2, vid+3, vid+1*4+2,
//                 vid+3, vid+1*4+3, vid+1*4+2,
//             ]);
//             normals.append(&mut vec![
//                 [0., 0., 1.],
//                 [0., 0., 1.],
//                 [0., 0., 1.],
//                 [0., 0., 1.],
//             ]);
//         }

//         // if id<heights.len()-1 && heights[id+1] < by {
//         //     indices.append(&mut vec![
//         //         vid+4, vid+6, vid+2, 
//         //         vid+4, vid+5, vid+3,
//         //     ]);
//         // }
//         // if id>16 && heights[id-16] < by {
//         //     indices.append(&mut vec![
//         //         vid-4-CHUNK_SIZE, vid-3-CHUNK_SIZE, vid+2, 
//         //         vid-4-CHUNK_SIZE, vid-2-CHUNK_SIZE, vid+3,
//         //     ]);
//         // }
//         // if id<heights.len()-16 && heights[id+16] < by {
//         //     indices.append(&mut vec![
//         //         vid+4+CHUNK_SIZE, vid+3+CHUNK_SIZE, vid+2, 
//         //         vid+4+CHUNK_SIZE, vid+2+CHUNK_SIZE, vid+3,
//         //     ]);
//         // }
//         id += 1;
//     }
// }
// let mut mesh = Mesh::new(bevy::render::mesh::PrimitiveTopology::TriangleList, RenderAssetUsages::default());
// mesh = mesh.with_inserted_attribute(Mesh::ATTRIBUTE_NORMAL, normals);
// // vec![
// // [0., 1., 0.],
// // [0., 1., 0.],
// // [0., 1., 0.],
// // [0., 1., 0.],
// // ]
// // );
// mesh = mesh.with_inserted_attribute(Mesh::ATTRIBUTE_POSITION, positions);
// mesh = mesh.with_inserted_indices(Indices::U16(indices));
// // mesh = mesh.with_inserted_attribute(Mesh::ATTRIBUTE_UV_0, vec![
// //     [0.0, 1.0], [0.5, 0.0], [1.0, 0.0], [0.5, 1.0]
// // ]);