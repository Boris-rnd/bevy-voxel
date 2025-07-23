#![allow(unused_imports, dead_code)]
use std::ops::RangeInclusive;

use bevy::{
    asset::RenderAssetUsages, pbr::{NotShadowCaster, NotShadowReceiver}, prelude::*, render::{batching::NoAutomaticBatching, render_resource::{Extent3d, ShaderType, TextureDimension, TextureFormat}, view::NoFrustumCulling}
};
use noise::{NoiseFn, Perlin};
use world::*;

pub mod build;
pub mod camera;
pub mod world;
use bevy::{
    prelude::*,
    reflect::TypePath,
    render::render_resource::{AsBindGroup, ShaderRef},
};

fn main() {
    let mut app = App::new();
    app.add_plugins((
        DefaultPlugins.set(AssetPlugin {
            watch_for_changes_override: Some(true),
            ..Default::default()
        }),
        MaterialPlugin::<CustomMaterial>::default(),
        // bevy::render::diagnostic::RenderDiagnosticsPlugin,
    ))
    .add_plugins(bevy::diagnostic::FrameTimeDiagnosticsPlugin::default())
    .add_plugins(iyes_perf_ui::PerfUiPlugin)
    .add_systems(Startup, setup)
    .add_systems(Update, update);
    app.run();
}

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
    let trans = Transform::from_xyz(0.0, 0.0, 2.0).looking_at(Vec3::ZERO, Vec3::Y);

    let spheres = &[
        sphere(vec3(0., 1., -1.2), 0.5, vec3(0.1, 0.2, 0.5)),
        // sphere(vec3(-1., 0., -1.), 0.5, vec3(0.8, 0.8, 0.8)),
        // sphere(vec3(1., 0., -1.), 0.5, vec3(0.8, 0.8, 0.8)),
        // sphere(vec3(0., -100.5, -1.), 100., vec3(0.8, 0.6, 0.2)),
    ];
    let spheres_buffer = buffers.add(bevy::render::storage::ShaderStorageBuffer::from(spheres));
    let mut boxes: Vec<world::Box> = vec![];
    let mut voxels: Vec<world::Voxel> = vec![];
    let mut voxel_chunks = vec![];
    let mut block_data: Vec<BlockData> = vec![];

    for x in -5..5 {
        for y in -5..5 {
            for z in -5..5 {
                voxel_chunks.push(voxel_chunk(vec3(x as _, y as _, z as _), 0));
            }
        }
    }
    let boxes_buffer = buffers.add(bevy::render::storage::ShaderStorageBuffer::from(boxes));
    let center = vec3(0., 0., 0.);


    let mut imgs_raw = Vec::new();
    for entry in std::fs::read_dir("assets/images").unwrap() {
        let img = image::ImageReader::open(entry.unwrap().path()).unwrap().decode().unwrap().to_rgba8();
        imgs_raw.push(img);
    }
    let width = imgs_raw[0].width();
    let height = imgs_raw[0].height();
    let layers = imgs_raw.len() as u32;
    let mut combined = image::ImageBuffer::new(width, height * layers);
    for (i, img) in imgs_raw.iter().enumerate() {
        image::GenericImage::copy_from(&mut combined, img, 0, i as u32 * height).unwrap();
    }

    let data = combined.into_raw(); // Vec<u8>
    let mut image = Image::new(
        Extent3d { width, height: height * layers, depth_or_array_layers: 1 },
        TextureDimension::D2,
        data,
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::RENDER_WORLD,
    );
    image.reinterpret_stacked_2d_as_array(layers);
    let atlas_handle = imgs.add(image);

    commands.spawn((
        Mesh3d(meshes.add(Cuboid::from_size(vec3(1.6, 0.9, 1.)))),
        MeshMaterial3d(materials.add(CustomMaterial {
            image_dimensions: window_query.single().unwrap().resolution.size(),
            spheres: spheres_buffer,
            camera: FragCamera {
                center,
                direction: look_at(center, vec3(0., 0., -1.)),
                fov: 90.,
            },
            boxes: boxes_buffer,
            atlas: atlas_handle,
            voxels: buffers.add(bevy::render::storage::ShaderStorageBuffer::from(voxels)),
            voxel_chunks: buffers.add(bevy::render::storage::ShaderStorageBuffer::from(voxel_chunks)),
            block_data: buffers.add(bevy::render::storage::ShaderStorageBuffer::from(block_data)),
        })),
        Transform::from_xyz(0.0, 0.0, 0.0),
    ));

    commands.spawn((Camera3d::default(), Camera::default(), trans));
}

fn look_at(origin: Vec3, look_at: Vec3) -> Vec3 {
    look_at - origin
}

fn update(
    mut cam: Query<&mut Transform, With<Camera>>,
    mut mats: ResMut<Assets<CustomMaterial>>,
    mut mat: Query<&mut MeshMaterial3d<CustomMaterial>>,
    mut imgs: ResMut<Assets<Image>>,
    time: Res<Time>,
    kb_input: Res<ButtonInput<KeyCode>>,
    mb_input: Res<ButtonInput<MouseButton>>,
    mut evr_motion: EventReader<bevy::input::mouse::MouseMotion>,
) {
    let mut cam = cam.single_mut().unwrap();
    let mat = mat.single_mut().unwrap();
    let mat = mats.get_mut(&mat.0).unwrap();

    if mb_input.pressed(MouseButton::Left) {
        let mut delta = Vec2::ZERO;
        for ev in evr_motion.read() {
            delta += ev.delta;
        }
        if delta != Vec2::ZERO {
            let sensitivity = vec2(1., -1.) * 0.002;

            let yaw = Quat::from_axis_angle(Vec3::Y, -delta.x * sensitivity.x);
            let right = Vec3::Y.cross(mat.camera.direction).normalize();
            let pitch = Quat::from_axis_angle(right, -delta.y * sensitivity.y);

            mat.camera.direction = (yaw * pitch * mat.camera.direction).normalize();
        }
    }

    let mut direction = Vec3::ZERO;
    let speed = 4.;

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
    direction = vec3(direction.x,0.,direction.z);
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
}


#[repr(C)]
#[derive(ShaderType, Debug, Clone)]
struct FragCamera {
    center: Vec3,
    direction: Vec3,
    fov: f32,
}

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
struct CustomMaterial {
    #[storage(2, read_only)]
    spheres: Handle<bevy::render::storage::ShaderStorageBuffer>,
    #[storage(3, read_only)]
    boxes: Handle<bevy::render::storage::ShaderStorageBuffer>,
    #[storage(6, read_only)]
    voxels: Handle<bevy::render::storage::ShaderStorageBuffer>,
    #[storage(7, read_only)]
    voxel_chunks: Handle<bevy::render::storage::ShaderStorageBuffer>,
    #[storage(8, read_only)]
    block_data: Handle<bevy::render::storage::ShaderStorageBuffer>,


    #[uniform(1)]
    camera: FragCamera,

    #[texture(4, dimension = "2d_array")]
    #[sampler(5)]
    atlas: Handle<Image>,

    #[uniform(100)]
    image_dimensions: Vec2,
}

impl Material for CustomMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/raytrace.wgsl".into()
    }
}
