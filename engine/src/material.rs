use super::*;

// #[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
// pub struct CustomMaterial {
//     // #[storage(2, read_only)]
//     // pub spheres: Handle<bevy::render::storage::ShaderStorageBuffer>,
//     // #[storage(3, read_only)]
//     // pub boxes: Handle<bevy::render::storage::ShaderStorageBuffer>,
//     // #[storage(6, read_only)]
//     // pub voxels: Handle<bevy::render::storage::ShaderStorageBuffer>,
    
//     #[uniform(0)]
//     pub camera: FragCamera,
//     #[storage(1, read_only)]
//     pub voxel_chunks: Handle<bevy::render::storage::ShaderStorageBuffer>,
//     #[storage(2, read_only)]
//     pub map_data: Handle<bevy::render::storage::ShaderStorageBuffer>,
//     #[texture(3, dimension = "2d_array")]
//     #[sampler(4)]
//     pub atlas: Handle<Image>,


//     /// Need 2 textures for accumulation, then we swap them as ping-pong
//     #[texture(5, dimension = "2d")]
//     pub accumulated_img: Handle<Image>,
//     // #[texture(10, dimension = "2d")]
//     // pub accumulated_img2: Handle<Image>,

// }

// impl Material2d for CustomMaterial {
//     fn fragment_shader() -> ShaderRef {
//         "shaders/raytrace-compiled.wgsl".into()
//     }
//     // fn alpha_mode(&self) -> AlphaMode2d {
//     //     AlphaMode2d::Mask(0.5)
//     // }
// }

// impl CustomMaterial {
//     pub fn new(
//         image_dimensions: Vec2,
//         center: Vec3,
//         game_world: Res<GameWorld>,
//         mut imgs: &mut ResMut<Assets<Image>>,
//         mut buffers: &mut ResMut<Assets<bevy::render::storage::ShaderStorageBuffer>>,
//     ) -> Self {
//         Self {
//             camera: FragCamera::new(center, vec3(0., 0., -1.)-center, 90., game_world.root_max_depth(), uvec2(image_dimensions.x as _, image_dimensions.y as _)),
//             atlas: get_atlas_handle(&mut imgs).unwrap(),

//             // spheres: buffers.add(ShaderStorageBuffer::from(game_world.spheres)),
//             // boxes: buffers.add(ShaderStorageBuffer::from(game_world.boxes)),
//             // voxels: buffers.add(ShaderStorageBuffer::from(game_world.voxels)),
//             voxel_chunks: buffers.add(ShaderStorageBuffer::from(game_world.voxel_chunks.clone())),
//             map_data: buffers.add(ShaderStorageBuffer::from(game_world.block_data.clone())),
//             accumulated_img: imgs.add({
//                 let mut image = Image::new_fill(
//                     Extent3d {
//                         width: image_dimensions.x as _,
//                         height: image_dimensions.y as _,
//                         depth_or_array_layers: 1,
//                     },
//                     TextureDimension::D2,
//                     &[0; 16],
//                     TextureFormat::Rgba32Float,
//                     RenderAssetUsages::default(),
//                 );
//                 image.texture_descriptor.usage = TextureUsages::TEXTURE_BINDING
//                     | TextureUsages::STORAGE_BINDING
//                     | TextureUsages::RENDER_ATTACHMENT;
//                 image
//             }),
//         }
//     }
// }

pub fn get_raw_atlas() -> Result<(Vec<u8>, UVec3)> {
    let mut imgs_raw = Vec::new();
    let additionnal_paths = vec![
        "engine/assets/textures/block/diamond_block.png",
        "engine/assets/textures/block/cobblestone.png",
        "engine/assets/textures/block/dirt.png",
        "engine/assets/textures/block/oak_log.png",
    ];
    let target_size = 32; // Define target size for width and height
    for entry in std::fs::read_dir("engine/assets/images").expect("Failed to read assets/images directory")
        .filter(|path| path.is_ok())
        .map(|path| path.unwrap().path())
        .chain(additionnal_paths.into_iter().map(|p| p.into()))
    {
        let img = image::ImageReader::open(entry).expect("Failed to read texture").decode().unwrap().to_rgba8();

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
        image::GenericImage::copy_from(&mut combined, img, 0, i as u32 * height).unwrap();
    }

    let data = combined.into_raw(); 
    Ok((data, uvec3(width,height,layers)))
}

pub fn get_atlas_handle(mut imgs: &mut ResMut<Assets<Image>>) -> Result<Handle<Image>> {
    let (data, size) = get_raw_atlas().unwrap();

    let mut image = Image::new(
        Extent3d {
            width: size.x,
            height: size.y * size.z,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        data,
        TextureFormat::R32Uint,
        RenderAssetUsages::RENDER_WORLD,
    );
    
    image.reinterpret_stacked_2d_as_array(size.z);
    Ok(imgs.add(image))
}




#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
pub struct PassthroughMaterial {
    #[uniform(0)]
    pub camera: FragCamera,
    #[storage(1, read_only)]
    pub accumulated_tex: Handle<ShaderStorageBuffer>,
    // #[storage(2, read_only)]
    // pub accumulated_tex2: Handle<ShaderStorageBuffer>,
}

impl Material2d for PassthroughMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/passthrough-compiled.wgsl".into()
    }
}
