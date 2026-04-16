// #![feature(generic_arg_infer)]
#![feature(vec_push_within_capacity)]
#![allow(unused, dead_code)]
// Temporary code to allow static mutable references
#![allow(static_mut_refs)]
#![allow(ambiguous_glob_reexports)]
use std::{cell::OnceCell, ops::RangeInclusive};

pub use bevy::prelude::*;
use bevy::render::{extract_resource::ExtractResourcePlugin, render_asset::RenderAssets, storage::GpuShaderStorageBuffer};
pub use bevy::{
    asset::RenderAssetUsages,
    color::palettes::css::WHITE,
    pbr::{NotShadowCaster, NotShadowReceiver},
    prelude::*,
    render::{
        batching::NoAutomaticBatching,
        render_resource::AsBindGroup,
        render_resource::{Extent3d, TextureDimension, TextureFormat, TextureUsages, ShaderType, ShaderRef},
        storage::ShaderStorageBuffer,
        view::NoFrustumCulling,
        
    },
    sprite::{AlphaMode2d, Material2d, Material2dPlugin},
};

pub mod build;
pub mod camera;
pub use camera::*;
use world::parser::load_world;
pub use world::*;
pub mod compute;
pub use compute::*;
pub mod material;
pub use material::*;

fn main() {
    // let world = gen_world();
    let world = load_world("engine/assets/world/sponza.vox").unwrap();
    let root_max_depth = world.root_max_depth();
    let mut app = App::new();
    app
    .insert_resource(world)
    .insert_resource(FragCamera::new(vec3(0.,10., 0.), vec3(0., 10., -1.), 90., root_max_depth, uvec2(800, 600)))
    .add_plugins((
        DefaultPlugins.set(AssetPlugin {
            watch_for_changes_override: Some(true),
            ..Default::default()
        }),
        // Material2dPlugin::<CustomMaterial>::default(),
        Material2dPlugin::<PassthroughMaterial>::default(),
        ExtractResourcePlugin::<ReadbackBuffer>::default(),
        ExtractResourcePlugin::<BeamReadbackBuffer>::default(),
        ExtractResourcePlugin::<AccumulatedTexture>::default(),
        ExtractResourcePlugin::<ComputeAtlas>::default(),
        ExtractResourcePlugin::<FragCamera>::default(),
        // bevy::render::diagnostic::RenderDiagnosticsPlugin,  
        bevy_app_compute::prelude::AppComputePlugin,
        // bevy_app_compute::prelude::AppComputeWorkerPlugin::<SimpleComputeWorker>::default()
        compute::GpuReadbackPlugin,
        compute::BeamGpuReadbackPlugin,
        bevy::diagnostic::FrameTimeDiagnosticsPlugin::default(),
        iyes_perf_ui::PerfUiPlugin,
    ))
    // .add_systems(Startup, (_setup, compute::setup))
    .add_systems(Startup, (_setup.after(compute::setup), compute::setup))
    .add_systems(Update, update)
    // .add_systems(Update, compute::test)
    // .add_systems(bevy::render::Render, compute::queue_compute_pass)
    ;
    app.run();
}
static mut WORLD_PTR: OnceCell<GameWorld> = OnceCell::new();

#[derive(Resource, bevy::render::extract_resource::ExtractResource, Clone)]
pub struct AccumulatedTexture((Handle<ShaderStorageBuffer>, Handle<ShaderStorageBuffer>));

fn _setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    window_query: Query<&Window, With<bevy::window::PrimaryWindow>>,
    mut materials: ResMut<Assets<PassthroughMaterial>>,
    mut buffers: ResMut<Assets<bevy::render::storage::ShaderStorageBuffer>>,
    mut imgs: ResMut<Assets<Image>>,
    asset_server: Res<AssetServer>,
    game_world: Res<GameWorld>,
    camera: Res<FragCamera>,
    accumulated_tex: Res<AccumulatedTexture>,
) {
    commands.spawn(iyes_perf_ui::prelude::PerfUiDefaultEntries::default());

    let center = vec3(-10., 10., -10.);

    let image_dimensions = window_query.single().unwrap().resolution.size();
    commands.spawn((
        Mesh2d(meshes.add(Rectangle::default())),
        MeshMaterial2d(materials.add(PassthroughMaterial {
            camera: camera.clone(),
            accumulated_tex: accumulated_tex.0.0.clone(),
            // accumulated_tex2: accumulated_tex.0.1.clone(),
        })),
        Transform::default().with_scale(image_dimensions.extend(0.0)),
    ));

    commands.spawn((Camera2d::default()));
}

fn update(
    // mut cam: Query<&Transform, With<Camera>>,
    mut mats: ResMut<Assets<PassthroughMaterial>>,
    mut mat: Query<(&mut MeshMaterial2d<PassthroughMaterial>, &mut Transform)>,
    mut imgs: ResMut<Assets<Image>>,
    time: Res<Time>,
    kb_input: Res<ButtonInput<KeyCode>>,
    mb_input: Res<ButtonInput<MouseButton>>,
    mut evr_motion: EventReader<bevy::input::mouse::MouseMotion>,
    window_query: Query<&Window, With<bevy::window::PrimaryWindow>>,
    mut frag_camera: ResMut<FragCamera>,
    // mut my_buffers: ResMut<ReadbackBuffer>,
    // mut buffers: ResMut<Assets<ShaderStorageBuffer>>,
    // mut buffers: ResMut<RenderAssets<GpuShaderStorageBuffer>>,
    mut accumulated_tex: Res<AccumulatedTexture>,
) {
    
    // let mut cam = cam.single_mut().unwrap();
    let mut camera = frag_camera;

    let mut mouse_delta = Vec2::ZERO;
    if mb_input.pressed(MouseButton::Left) {
        for ev in evr_motion.read() {
            mouse_delta += ev.delta;
        }
        if mouse_delta != Vec2::ZERO {
            let sensitivity = vec2(1., -1.) * 0.002;

            let yaw = Quat::from_axis_angle(Vec3::Y, -mouse_delta.x * sensitivity.x);
            let right = Vec3::Y.cross(camera.direction).normalize();
            let pitch = Quat::from_axis_angle(right, -mouse_delta.y * sensitivity.y);

            camera.direction = (yaw * pitch * camera.direction).normalize();
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

    if kb_input.pressed(KeyCode::ControlLeft) {
        speed *= 10.;
    }

    if kb_input.pressed(KeyCode::KeyW) {
        direction += camera.direction;
    }

    if kb_input.pressed(KeyCode::KeyS) {
        direction -= camera.direction;
    }

    if kb_input.pressed(KeyCode::KeyA) {
        direction -= camera.direction.cross(Vec3::Y);
    }

    if kb_input.pressed(KeyCode::KeyD) {
        direction += camera.direction.cross(Vec3::Y);
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

    camera.center += move_delta;

    let (mat, mut mat_trans) = mat.single_mut().unwrap();
    let mat = mats.get_mut(&mat.0).unwrap();
    
    let win_size = window_query.single().unwrap().resolution.size();
    mat_trans.scale = win_size.extend(0.0);

    camera.accumulated_frames += 1;
    let new_size = uvec2(win_size.x as _, win_size.y as _);
    if new_size != mat.camera.img_dims {
        info!("Resizing image from {:?} to {:?}", mat.camera.img_dims, new_size);
        camera.img_dims = new_size;
        // dbg!(buffers.get_mut(&mut accumulated_tex.0).unwrap().buffer.size());
        // buffers.get_mut(&mut accumulated_tex.0).unwrap().buffer.destroy();
        // let handle = buffers.add(ShaderStorageBuffer::from(vec![255u32; (new_size.x*new_size.y) as usize]));
        // bind_group.0
    }
    // if camera.accumulated_frames%2==0 {
    //     mat.accumulated_tex = accumulated_tex.0.0.clone();
    // } else {
    //     mat.accumulated_tex = accumulated_tex.0.1.clone();
    // }
    mat.camera.accumulated_frames = camera.accumulated_frames;
    if mat.camera != *camera {
        camera.accumulated_frames = 0;
        mat.camera = camera.clone();
    }

    
    // dbg!(&buf.data, buf.buffer_description.size);
    // buf.slice(..).map_async(bevy::render::render_resource::MapMode::Write, |a| {
    //     a.unwrap();
    // });
    // *buf.slice(..).get_mapped_range_mut() = mat.camera.clone();
    // let data = buffers.get_mut(&mut my_buffers.camera_uniform).unwrap().data.as_ref().unwrap();
    // dbg!(&unsafe {std::mem::transmute::<_, &FragCamera>(data.as_slice().as_ptr() as *const FragCamera)});
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
    mut mats: ResMut<Assets<PassthroughMaterial>>,
    mut mat: Query<(&mut MeshMaterial2d<PassthroughMaterial>, &mut Transform)>,
) {
    let (mut mat, mut trans) = mat.single_mut().unwrap();
    let mat = mats.get_mut(&mat.0).unwrap();
}
