use super::*;

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
pub struct CustomMaterial {
    #[storage(2, read_only)]
    pub spheres: Handle<bevy::render::storage::ShaderStorageBuffer>,
    #[storage(3, read_only)]
    pub boxes: Handle<bevy::render::storage::ShaderStorageBuffer>,
    #[storage(6, read_only)]
    pub voxels: Handle<bevy::render::storage::ShaderStorageBuffer>,
    #[storage(7, read_only)]
    pub voxel_chunks: Handle<bevy::render::storage::ShaderStorageBuffer>,
    #[storage(8, read_only)]
    pub block_data: Handle<bevy::render::storage::ShaderStorageBuffer>,

    #[uniform(1)]
    pub camera: FragCamera,

    #[texture(4, dimension = "2d_array")]
    #[sampler(5)]
    pub atlas: Handle<Image>,

    /// Need 2 textures for accumulation, then we swap them as ping-pong
    #[texture(9, dimension = "2d")]
    pub accumulated_img: Handle<Image>,
    #[texture(10, dimension = "2d")]
    pub accumulated_img2: Handle<Image>,

    #[uniform(100)]
    pub image_dimensions: Vec2,
}

impl Material2d for CustomMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/raytrace-compiled.wgsl".into()
    }
    // fn alpha_mode(&self) -> AlphaMode2d {
    //     AlphaMode2d::Mask(0.5)
    // }
}

impl CustomMaterial {
    pub fn new(
        image_dimensions: Vec2,
        center: Vec3,
        world: GameWorld,
        mut imgs: &mut ResMut<Assets<Image>>,
        mut buffers: &mut ResMut<Assets<bevy::render::storage::ShaderStorageBuffer>>,
    ) -> Self {
        Self {
            image_dimensions,
            camera: FragCamera {
                center,
                direction: vec3(0., 0., -1.)-center,
                fov: 90.,
                root_max_depth: world.root_max_depth(),
                accumulated_frames: 0,
            },
            atlas: get_atlas_handle(&mut imgs).unwrap(),

            spheres: buffers.add(ShaderStorageBuffer::from(world.spheres)),
            boxes: buffers.add(ShaderStorageBuffer::from(world.boxes)),
            voxels: buffers.add(ShaderStorageBuffer::from(world.voxels)),
            voxel_chunks: buffers.add(ShaderStorageBuffer::from(world.voxel_chunks)),
            block_data: buffers.add(ShaderStorageBuffer::from(world.block_data)),
            accumulated_img: imgs.add({
                let mut image = Image::new_fill(
                    Extent3d {
                        width: image_dimensions.x as _,
                        height: image_dimensions.y as _,
                        depth_or_array_layers: 1,
                    },
                    TextureDimension::D2,
                    &[0; 16],
                    TextureFormat::Rgba32Float,
                    RenderAssetUsages::default(),
                );
                image.texture_descriptor.usage = TextureUsages::TEXTURE_BINDING
                    | TextureUsages::STORAGE_BINDING
                    | TextureUsages::RENDER_ATTACHMENT;
                image
            }),
            accumulated_img2: imgs.add({
                let mut image = Image::new_fill(
                    Extent3d {
                        width: image_dimensions.x as _,
                        height: image_dimensions.y as _,
                        depth_or_array_layers: 1,
                    },
                    TextureDimension::D2,
                    &[0; 16],
                    TextureFormat::Rgba32Float,
                    RenderAssetUsages::default(),
                );
                image.texture_descriptor.usage = TextureUsages::TEXTURE_BINDING
                    | TextureUsages::STORAGE_BINDING
                    | TextureUsages::RENDER_ATTACHMENT;
                image
            }),
        }
    }
}

pub fn get_atlas_handle(mut imgs: &mut ResMut<Assets<Image>>) -> Result<Handle<Image>> {
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
    info!("Atlas size: {}x{}x{}", width, height, layers);
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
