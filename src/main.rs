#![allow(unused, dead_code)]
use std::{cell::OnceCell, ops::RangeInclusive};

use bevy::{
    asset::RenderAssetUsages,
    pbr::{NotShadowCaster, NotShadowReceiver},
    prelude::*,
    render::{
        batching::NoAutomaticBatching,
        render_resource::{Extent3d, ShaderType, TextureDimension, TextureFormat},
        storage::ShaderStorageBuffer,
        view::NoFrustumCulling,
    },
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
    let trans = Transform::from_xyz(0.0, 0.0, 2.0).looking_at(Vec3::ZERO, Vec3::Y);

    let mut world = GameWorld {
        block_data: vec![],
        voxel_chunks: vec![voxel_chunk(0, 0, 0)],
        ..Default::default()
    };
    unsafe {
        WORLD_PTR.set(world).unwrap();
        std::panic::set_hook(std::boxed::Box::new(|info| {
        eprintln!("Panic occurred: {:?}", info);
        eprintln!("{}", info.payload().downcast_ref::<String>().unwrap_or(&"No message".to_string()));
        eprintln!("World state at panic: {:?}", WORLD_PTR.get().unwrap());
        eprintln!("Prettier: {}", WORLD_PTR.get().unwrap().pretty_print());
    }));
        dbg!(WORLD_PTR.get().unwrap());
    }
    let mut world = unsafe { WORLD_PTR.get_mut().unwrap() };

    let perlin = Perlin::new(1);
    for x in 0..16 {
        for y in 1..3 {
            for z in 0..16 {
                    // world.set_data_in_chunk(0, LocalPos::new(x as u8, y as u8, z as u8), MapData::Chunk(3));
                    // assert_eq!(world.get_data_in_chunk(0, LocalPos::new(x as u8, y as u8, z as u8)), Some(MapData::Chunk(3)));

                // if perlin.get([x as f64, y as f64, z as f64])>0.0 {
                world.set_block(
                    ivec3(x, y*5%15, z),
                    MapData::Block(((x + y + z) % 15) as u32),
                );
                // dbg!(world.get_block(ivec3(x * 2, y, z)), &world.block_data);
                // }
                // let mut layer = 1;
                // if y ==4{layer=0;}
                // world.set_block(ivec3(x,y,z), MapData::block(layer))
            }
        }
    }

    println!("------------------------------------------------");
    println!("World size: {:?}", world.root_size());
    dbg!(&world.voxel_chunks.len());
    dbg!(&world.block_data.len());

    for x in 0..16 {
        for y in 1..3 {
            for z in 0..16 {
                assert_eq!(
                    world.get_block(ivec3(x, y*5%15, z)),
                    Some(&MapData::Block(((x + y + z) % 15) as u32)).copied(),
                    "{x},{y},{z}, {:?} {:?}", world.voxel_chunks, world.block_data
                );
            }
        }
    }
    // assert_eq!(world.get_block(ivec3(0, 10, 0)), None);
    // world.set_block(ivec3(0, 10, 0), MapData::Block(1));
    // assert_eq!(world.get_block(ivec3(0, 10, 0)), Some(&MapData::Block(1)).copied());
    // world.set_data_in_chunk(0, LocalPos::new(1,1,1), MapData::Block(2));
    // dbg!(&world);

    let center = vec3(-10., 10., -10.);
    std::panic::take_hook();
    let mut world = unsafe { WORLD_PTR.take().unwrap() };
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::from_size(vec3(1.6, 0.9, 1.)))),
        MeshMaterial3d(materials.add(CustomMaterial {
            image_dimensions: window_query.single().unwrap().resolution.size(),
            camera: FragCamera {
                center,
                direction: look_at(center, vec3(0., 0., -1.)),
                fov: 90.,
            },
            atlas: get_atlas_handle(imgs).unwrap(),

            spheres: buffers.add(ShaderStorageBuffer::from(world.spheres)),
            boxes: buffers.add(ShaderStorageBuffer::from(world.boxes)),
            voxels: buffers.add(ShaderStorageBuffer::from(world.voxels)),
            voxel_chunks: buffers.add(ShaderStorageBuffer::from(world.voxel_chunks)),
            block_data: buffers.add(ShaderStorageBuffer::from(world.block_data)),
        })),
        Transform::from_xyz(0.0, 0.0, 0.0),
    ));

    commands.spawn((Camera3d::default(), Camera::default(), trans));
}

fn get_atlas_handle(mut imgs: ResMut<Assets<Image>>) -> Result<Handle<Image>> {
    let mut imgs_raw = Vec::new();
    let additionnal_paths = vec![
        "assets/textures/block/diamond_block.png",
        "assets/textures/block/cobblestone.png",
        "assets/textures/block/dirt.png",
        "assets/textures/block/oak_log.png",
    ];
    let target_size = 32; // Define target size for width and height
    for entry in std::fs::read_dir("assets/images")?
        .filter(|path| path.is_ok())
        .map(|path| path.unwrap().path())
        .chain(additionnal_paths.into_iter().map(|p| p.into()))
    {
        let img = image::ImageReader::open(entry)?.decode()?.to_rgba8();

        let resized = image::imageops::resize(
            &img,
            target_size,
            target_size,
            image::imageops::FilterType::Nearest,
        );

        imgs_raw.push(resized);
    }

    let width = imgs_raw[0].width();
    let height = imgs_raw[0].height();
    let layers = imgs_raw.len() as u32;
    println!("Atlas size: {}x{}x{}", width, height, layers);
    if imgs_raw
        .iter()
        .any(|img| img.width() != width || img.height() != height)
    {
        panic!("All images must have the same dimensions for atlas creation.");
    }
    let mut combined = image::ImageBuffer::new(width, height * layers);
    for (i, img) in imgs_raw.iter().enumerate() {
        image::GenericImage::copy_from(&mut combined, img, 0, i as u32 * height)?;
    }

    let data = combined.into_raw(); // Vec<u8>
    let mut image = Image::new(
        Extent3d {
            width,
            height: height * layers,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        data,
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::RENDER_WORLD,
    );
    image.reinterpret_stacked_2d_as_array(layers);
    Ok(imgs.add(image))
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
