#![allow(unused, dead_code)]
// Temporary code to allow static mutable references
#![allow(static_mut_refs)]
#![allow(ambiguous_glob_reexports)]
use std::{cell::OnceCell, ops::RangeInclusive};

pub use bevy::prelude::*;
pub use bevy::{
    asset::RenderAssetUsages,
    color::palettes::css::WHITE,
    pbr::{NotShadowCaster, NotShadowReceiver},
    prelude::*,
    render::{
        batching::NoAutomaticBatching,
        render_resource::AsBindGroup,
        render_resource::{Extent3d, TextureDimension, TextureFormat, TextureUsages},
        storage::ShaderStorageBuffer,
        view::NoFrustumCulling,
    },
    sprite::{AlphaMode2d, Material2d, Material2dPlugin},
};
pub use bevy_app_compute::prelude::*;
pub use noise::{NoiseFn, Perlin};

pub mod build;
pub mod camera;
pub use camera::*;
pub mod world;
pub use world::*;
pub mod compute;
pub use compute::*;
pub mod material;
pub use material::*;

fn main() {
    let mut app = App::new();
    app.add_plugins((
        DefaultPlugins.set(AssetPlugin {
            watch_for_changes_override: Some(true),
            ..Default::default()
        }),
        Material2dPlugin::<CustomMaterial>::default(),
        // bevy::render::diagnostic::RenderDiagnosticsPlugin,
    ))
    .add_plugins(AppComputePlugin)
    .add_plugins(bevy_app_compute::prelude::AppComputeWorkerPlugin::<
        SimpleComputeWorker,
    >::default())
    .add_plugins(bevy::diagnostic::FrameTimeDiagnosticsPlugin::default())
    .add_plugins(iyes_perf_ui::PerfUiPlugin)
    .add_systems(Startup, setup)
    .add_systems(Update, compute::compute_update)
    .add_systems(Update, update)
    ;
    app.run();
}
static mut WORLD_PTR: OnceCell<GameWorld> = OnceCell::new();

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    window_query: Query<&Window, With<bevy::window::PrimaryWindow>>,
    mut materials: ResMut<Assets<CustomMaterial>>,
    mut buffers: ResMut<Assets<bevy::render::storage::ShaderStorageBuffer>>,
    mut imgs: ResMut<Assets<Image>>,
    asset_server: Res<AssetServer>,
) {
    commands.spawn(iyes_perf_ui::prelude::PerfUiDefaultEntries::default());

    let mut world = GameWorld {
        block_data: vec![],
        voxel_chunks: vec![voxel_chunk(0, 0, 0)],
        ..Default::default()
    };
    let set_panic_h = false;
    unsafe {
        WORLD_PTR.set(world).unwrap();
        if set_panic_h {
            std::panic::set_hook(std::boxed::Box::new(|info| {
                eprintln!("Panic occurred: {:?}", info);
                eprintln!(
                    "{}",
                    info.payload()
                        .downcast_ref::<String>()
                        .unwrap_or(&"No message".to_string())
                );
                eprintln!("World state at panic: {:?}", WORLD_PTR.get().unwrap());
                eprintln!("Prettier: {}", WORLD_PTR.get().unwrap().pretty_print());
            }));
        }
    }
    let mut world = unsafe { WORLD_PTR.get_mut().unwrap() };

    let perlin = Perlin::new(1);
    for x in 0..world.root_size() as i32 {
        for y in 1..3 {
            for z in 0..world.root_size() as i32 {
                // if perlin.get([x as f64, y as f64, z as f64])>0.0 {
                world.set_block(
                    ivec3(
                        x,
                        ((perlin.get([x as f64 / 20., z as f64 / 20.]) * 20.) as i32 + y).abs(),
                        z,
                    ),
                    MapData::Block(((x + y + z) % 15) as u32),
                );
            }
        }
    }
    for x in 0..world.root_size() as i32 {
        for y in 1..3 {
            for z in 0..world.root_size() as i32 {
                // if perlin.get([x as f64, y as f64, z as f64])>0.0 {
                assert_eq!(
                    world.get_block(ivec3(
                        x,
                        ((perlin.get([x as f64 / 20., z as f64 / 20.]) * 20.) as i32 + y).abs(),
                        z
                    )),
                    Some(MapData::Block(((x + y + z) % 15) as u32)),
                    "{x},{y},{z}, {:?} {:?}",
                    world.voxel_chunks,
                    world.block_data
                );
            }
        }
    }

    info!("World size: {:?}", world.root_size());
    debug!("{}", &world.voxel_chunks.len());
    debug!("{}", &world.block_data.len());

    let center = vec3(-10., 10., -10.);
    if set_panic_h {
        std::panic::take_hook();
    }
    let mut world = unsafe { WORLD_PTR.take().unwrap() };
    let image_dimensions = window_query.single().unwrap().resolution.size();
    commands.spawn((
        Mesh2d(meshes.add(Rectangle::default())),
        MeshMaterial2d(materials.add(CustomMaterial::new(
            image_dimensions,
            center,
            world,
            &mut imgs,
            &mut buffers,
        ))),
        Transform::default().with_scale(image_dimensions.extend(0.0)),
    ));

    commands.spawn((Camera2d::default()));
}

fn update(
    // mut cam: Query<&Transform, With<Camera>>,
    mut mats: ResMut<Assets<CustomMaterial>>,
    mut mat: Query<(&mut MeshMaterial2d<CustomMaterial>, &mut Transform)>,
    mut imgs: ResMut<Assets<Image>>,
    time: Res<Time>,
    kb_input: Res<ButtonInput<KeyCode>>,
    mb_input: Res<ButtonInput<MouseButton>>,
    mut evr_motion: EventReader<bevy::input::mouse::MouseMotion>,
    window_query: Query<&Window, With<bevy::window::PrimaryWindow>>,
) {
    // let mut cam = cam.single_mut().unwrap();
    let (mat, mut mat_trans) = mat.single_mut().unwrap();

    let mat = mats.get_mut(&mat.0).unwrap();

    let mut mouse_delta = Vec2::ZERO;
    if mb_input.pressed(MouseButton::Left) {
        for ev in evr_motion.read() {
            mouse_delta += ev.delta;
        }
        if mouse_delta != Vec2::ZERO {
            let sensitivity = vec2(1., -1.) * 0.002;

            let yaw = Quat::from_axis_angle(Vec3::Y, -mouse_delta.x * sensitivity.x);
            let right = Vec3::Y.cross(mat.camera.direction).normalize();
            let pitch = Quat::from_axis_angle(right, -mouse_delta.y * sensitivity.y);

            mat.camera.direction = (yaw * pitch * mat.camera.direction).normalize();
        }
    }

    let mut direction = Vec3::ZERO;
    let mut speed = 4.;
    if kb_input.pressed(KeyCode::ShiftLeft) {
        speed *= 4.;
    }
    if kb_input.pressed(KeyCode::AltLeft) {
        speed *= 4.;
    }

    if kb_input.pressed(KeyCode::KeyW) {
        direction += mat.camera.direction;
    }

    if kb_input.pressed(KeyCode::KeyS) {
        direction -= mat.camera.direction;
    }

    if kb_input.pressed(KeyCode::KeyA) {
        direction -= mat.camera.direction.cross(Vec3::Y);
    }

    if kb_input.pressed(KeyCode::KeyD) {
        direction += mat.camera.direction.cross(Vec3::Y);
    }
    direction = vec3(direction.x, 0., direction.z);
    if kb_input.pressed(KeyCode::Space) {
        direction.y += 1.;
    }

    if kb_input.pressed(KeyCode::ShiftLeft) {
        direction.y -= 1.;
    }

    // Progressively update the player's position over time. Normalize the
    // direction vector to prevent it from exceeding a magnitude of 1 when
    // moving diagonally.
    let move_delta = direction.normalize_or_zero() * speed * time.delta_secs();
    // cam.translation += move_delta.extend(0.);

    mat.camera.center += move_delta;
    mat.image_dimensions = window_query.single().unwrap().resolution.size();
    mat_trans.scale = window_query.single().unwrap().resolution.size().extend(0.0);

    mat.camera.accumulated_frames += 1;
    // let mut img = imgs.get_mut(&mut mat.accumulated_img).unwrap();
    // if uvec2(mat.image_dimensions.x as _, mat.image_dimensions.y as _) != img.size()
    //     || move_delta != Vec3::ZERO
    //     || mouse_delta != Vec2::ZERO
    // {
    //     {
    //         let mut img_data = img.data.as_mut().unwrap();
    //         *img_data = vec![
    //             0;
    //             (mat.image_dimensions.x as usize * mat.image_dimensions.y as usize * 16)
    //                 as usize
    //         ];
    //     }
    //     let mut img2 = imgs.get_mut(&mut mat.accumulated_img2).unwrap();
    //     *img2.data.as_mut().unwrap() = vec![
    //         0;
    //         (mat.image_dimensions.x as usize * mat.image_dimensions.y as usize * 16)
    //             as usize
    //     ];
    //     mat.camera.accumulated_frames = 0;
    // }
    // let prev = mat.accumulated_img.clone();
    // mat.accumulated_img = mat.accumulated_img2.clone();
    // mat.accumulated_img2 = prev;
}

fn lods(
    mut mats: ResMut<Assets<CustomMaterial>>,
    mut mat: Query<(&mut MeshMaterial2d<CustomMaterial>, &mut Transform)>,
) {
    let (mut mat, mut trans) = mat.single_mut().unwrap();
    let mat = mats.get_mut(&mat.0).unwrap();
}
