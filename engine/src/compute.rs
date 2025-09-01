use super::*;
use bevy::{
    prelude::*,
    render::{
        extract_resource::{ExtractResource, ExtractResourcePlugin},
        gpu_readback::{Readback, ReadbackComplete},
        render_asset::{RenderAssetUsages, RenderAssets},
        render_graph::{self, RenderGraph, RenderLabel},
        render_resource::{
            binding_types::{
                storage_buffer, storage_buffer_read_only, texture_storage_2d, uniform_buffer,
                uniform_buffer_sized,
            },
            *,
        },
        renderer::{RenderContext, RenderDevice},
        storage::{GpuShaderStorageBuffer, ShaderStorageBuffer},
        texture::GpuImage,
        Render, RenderApp, RenderSet,
    },
};

#[derive(Resource)]
pub struct CameraUniform(UniformBuffer<FragCamera>);
#[derive(Resource)]
pub struct BeamCameraUniform(UniformBuffer<FragCamera>);

#[derive(Resource, ExtractResource, Clone)]
pub struct ReadbackBuffer {
    pub buffers: Vec<Handle<ShaderStorageBuffer>>,
}

#[derive(Resource, ExtractResource, Clone)]
pub struct ComputeAtlas(Handle<Image>);

pub struct GpuReadbackPlugin;
impl Plugin for GpuReadbackPlugin {
    fn build(&self, _app: &mut App) {}

    fn finish(&self, app: &mut App) {
        let render_app = app.sub_app_mut(RenderApp);
        render_app.init_resource::<ComputePipeline>().add_systems(
            Render,
            ((prepare_bind_group)
                .in_set(RenderSet::PrepareBindGroups)
                // We don't need to recreate the bind group every frame
                .run_if(not(resource_exists::<GpuBufferBindGroup>)), resize_cameras.after(prepare_bind_group)),
        );
        // Add the compute node as a top level node to the render graph
        // This means it will only execute once per frame
        render_app
            .world_mut()
            .resource_mut::<RenderGraph>()
            .add_node(ComputeNodeLabel, ComputeNode::default());
    }
}

// pub fn queue_compute_pass(
//     mut world: &mut World,
//     pipeline: Res<ComputePipeline>,
//     mut render_pass: ResMut<RenderGraph>,
//     camera: Res<FragCamera>,
// ) {

//     let pipeline_cache = world.resource::<PipelineCache>();
//     let pipeline = world.resource::<ComputePipeline>();
//     let bind_group = world.resource::<GpuBufferBindGroup>();

//     // dbg!(world.resource::<FragCamera>().img_dims);

//     if let Some(init_pipeline) = pipeline_cache.get_compute_pipeline(pipeline.pipeline) {
//         let mut pass =
//             render_context
//                 .command_encoder()
//                 .begin_compute_pass(&ComputePassDescriptor {
//                     label: Some("GPU readback compute pass"),
//                     ..default()
//                 });

//         pass.set_bind_group(0, &bind_group.0, &[]);
//         pass.set_pipeline(init_pipeline);
//         pass.dispatch_workgroups(
//             world.resource::<FragCamera>().img_dims.x as _,
//             world.resource::<FragCamera>().img_dims.y as _,
//             1,
//         );
//     }
// }

pub fn resize_cameras(
    mut frag_camera: ResMut<FragCamera>,
    mut cam_uni: ResMut<CameraUniform>,
    mut beam_cam_uni: ResMut<BeamCameraUniform>,
    

    render_device: Res<RenderDevice>,
    queue: Res<bevy::render::renderer::RenderQueue>,
) {
    // dbg!(&frag_camera);
    cam_uni.0.set(frag_camera.clone());
    cam_uni.0.write_buffer(&render_device, &queue);
    beam_cam_uni.0.set(frag_camera.clone());
    beam_cam_uni.0.write_buffer(&render_device, &queue);
    // buf.set_data(mat.camera.clone());
}

fn prepare_bind_group(
    mut commands: Commands,
    pipeline: Res<ComputePipeline>,
    render_device: Res<RenderDevice>,
    my_buffers: Res<ReadbackBuffer>,
    atlas: Res<ComputeAtlas>,
    image: Res<AccumulatedTexture>,
    max_depth_buffer: Res<BeamReadbackBuffer>,
    buffers: Res<RenderAssets<GpuShaderStorageBuffer>>,
    camera: Res<FragCamera>,
    images: Res<RenderAssets<GpuImage>>,
    queue: Res<bevy::render::renderer::RenderQueue>,
) {
    let mut cam_buf = UniformBuffer::from(camera.clone());
    cam_buf.write_buffer(&render_device, &queue);

    let mut entries: Vec<(usize, BindingResource<'_>)>  = vec![
        (0, buffers
            .get(&image.0.0)
            .unwrap()
            .buffer
            .as_entire_binding()),
        (1, cam_buf.binding().unwrap()),
        (2, buffers
            .get(&max_depth_buffer.max_depth_buffer)
            .unwrap()
            .buffer
            .as_entire_binding()),
        (3, images.get(&atlas.0).unwrap().texture_view.into_binding()),
    ];

    for (i, b) in my_buffers.buffers.iter().enumerate() {
        entries.push((4 + i, buffers.get(b).unwrap().buffer.as_entire_binding()));
    }

    let bind_group = render_device.create_bind_group(
        None,
        &pipeline.layout,
        &entries.iter().map(|(i, binding)| BindGroupEntry {
            binding: *i as u32,
            resource: binding.clone(),
        }).collect::<Vec<_>>(),
    );
    commands.insert_resource(CameraUniform(cam_buf));
    commands.insert_resource(GpuBufferBindGroup(bind_group));
}

fn beam_prepare_bind_group(
    mut commands: Commands,
    pipeline: Res<BeamComputePipeline>,
    render_device: Res<RenderDevice>,
    world_buffers: Res<ReadbackBuffer>,
    my_buffers: Res<BeamReadbackBuffer>,
    buffers: Res<RenderAssets<GpuShaderStorageBuffer>>,
    camera: Res<FragCamera>,
    queue: Res<bevy::render::renderer::RenderQueue>,
) {
    let mut cam_buf = UniformBuffer::from(camera.clone());
    cam_buf.write_buffer(&render_device, &queue);

    let mut entries: Vec<(usize, BindingResource<'_>)>  = vec![
        (0, buffers
            .get(&my_buffers.max_depth_buffer)
            .unwrap()
            .buffer
            .as_entire_binding()),
        (1, cam_buf.binding().unwrap()),
    ];

    for (i, b) in world_buffers.buffers.iter().enumerate() {
        entries.push((2 + i, buffers.get(b).unwrap().buffer.as_entire_binding()));
    }

    let bind_group = render_device.create_bind_group(
        None,
        &pipeline.layout,
        &entries.iter().map(|(i, binding)| BindGroupEntry {
            binding: *i as u32,
            resource: binding.clone(),
        }).collect::<Vec<_>>(),
    );
    commands.insert_resource(BeamCameraUniform(cam_buf));
    commands.insert_resource(BeamGpuBufferBindGroup(bind_group));
}

#[derive(Resource)]
pub struct GpuBufferBindGroup(pub BindGroup);
pub fn setup(
    mut commands: Commands,
    mut images: ResMut<Assets<Image>>,
    mut buffers: ResMut<Assets<ShaderStorageBuffer>>,
    window_query: Query<&Window, With<bevy::window::PrimaryWindow>>,
    game_world: Res<GameWorld>,
    camera: Res<FragCamera>,
) {
    let win_size = window_query.single().unwrap().resolution.size();
    // Create a storage texture with some data
    // let size = Extent3d {
    //     width: win_size.x as _,
    //     height: win_size.y as _,
    //     ..default()
    // };
    // // We create an uninitialized image since this texture will only be used for getting data out
    // // of the compute shader, not getting data in, so there's no reason for it to exist on the CPU
    // let mut image = Image::new_uninit(
    //     size,
    //     TextureDimension::D2,
    //     TextureFormat::R32Uint,
    //     RenderAssetUsages::RENDER_WORLD,
    // );
    // // We also need to enable the COPY_SRC, as well as STORAGE_BINDING so we can use it in the
    // // compute shader
    // image.texture_descriptor.usage |= TextureUsages::COPY_SRC | TextureUsages::STORAGE_BINDING;
    let (data, size) = get_raw_atlas().unwrap();
    let mut image = Image::new(
        Extent3d {
            width: size.x,
            height: size.y * size.z,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        data,
        TextureFormat::Rgba8Unorm,
        RenderAssetUsages::RENDER_WORLD,
    );
    image.texture_descriptor.usage |= TextureUsages::COPY_SRC | TextureUsages::STORAGE_BINDING;
    image.reinterpret_stacked_2d_as_array(size.z);
    
    commands.insert_resource(ComputeAtlas(images.add(image)));

    let mut my_buffers = Vec::with_capacity(8);
    my_buffers.push(buffers.add(ShaderStorageBuffer::from(game_world.voxel_chunks.clone())));
    for v in game_world.block_data.iter() {
        my_buffers.push(buffers.add(ShaderStorageBuffer::from(v.clone())));
    }
    commands.insert_resource(ReadbackBuffer { buffers: my_buffers });
    commands.insert_resource(AccumulatedTexture((buffers.add(ShaderStorageBuffer::from(
        vec![0u32; (1920 * 1080) as usize],
    )), buffers.add(ShaderStorageBuffer::from(
        vec![0u32; (1920 * 1080) as usize],
    )))));

    commands.insert_resource(BeamReadbackBuffer {
        max_depth_buffer: buffers.add(ShaderStorageBuffer::from(
            vec![0.0f32; (1920 * 1080)/4 as usize],
        )),
    });
}
#[derive(Resource)]
pub struct ComputePipeline {
    layout: BindGroupLayout,
    pipeline: CachedComputePipelineId,
}

impl FromWorld for ComputePipeline {
    fn from_world(world: &mut World) -> Self {
        let render_device = world.resource::<RenderDevice>();
        let layout = render_device.create_bind_group_layout(
            Some("Bind group layout compute"),
            &BindGroupLayoutEntries::sequential(
                ShaderStages::COMPUTE,
                (
                    storage_buffer::<Vec<u32>>(false),
                    uniform_buffer::<FragCamera>(false),
                    storage_buffer_read_only::<Vec<f32>>(false),
                    binding_types::texture_storage_2d_array(TextureFormat::Rgba8Unorm, StorageTextureAccess::ReadOnly),
                    storage_buffer_read_only::<Vec<VoxelChunk>>(false),
                    storage_buffer_read_only::<Vec<MapDataPacked>>(false),
                    storage_buffer_read_only::<Vec<MapDataPacked>>(false),
                    storage_buffer_read_only::<Vec<MapDataPacked>>(false),
                    storage_buffer_read_only::<Vec<MapDataPacked>>(false),
                ),
            ),
        );
        let shader = world.load_asset("shaders/raytrace-compiled.wgsl");
        let pipeline_cache = world.resource::<PipelineCache>();
        let pipeline = pipeline_cache.queue_compute_pipeline(ComputePipelineDescriptor {
            label: Some("GPU readback compute shader".into()),
            layout: vec![layout.clone()],
            push_constant_ranges: Vec::new(),
            shader: shader.clone(),
            shader_defs: vec![ShaderDefVal::UInt("_CHUNK_SIZE".to_string(), CHUNK_SIZE as u32)],
            entry_point: "main".into(),
            zero_initialize_workgroup_memory: false,
        });
        ComputePipeline { layout, pipeline }
    }
}

/// Label to identify the node in the render graph
#[derive(Debug, Hash, PartialEq, Eq, Clone, RenderLabel)]
struct ComputeNodeLabel;

/// The node that will execute the compute shader
#[derive(Default)]
struct ComputeNode {}
impl render_graph::Node for ComputeNode {
    fn run(
        &self,
        _graph: &mut render_graph::RenderGraphContext,
        render_context: &mut RenderContext,
        world: &World,
    ) -> Result<(), render_graph::NodeRunError> {
        if world.get_resource::<FragCamera>().is_none() {
            info!("Couldn't get frag camera, skipping compute pass.");
            return Ok(());
        }
        let pipeline_cache = world.resource::<PipelineCache>();
        let pipeline = world.resource::<ComputePipeline>();
        let bind_group = world.resource::<GpuBufferBindGroup>();
        let camera = world.resource::<FragCamera>();

        // dbg!(world.resource::<FragCamera>());

        if let Some(init_pipeline) = pipeline_cache.get_compute_pipeline(pipeline.pipeline) {
            let mut pass =
                render_context
                    .command_encoder()
                    .begin_compute_pass(&ComputePassDescriptor {
                        label: Some("GPU readback compute pass"),
                        ..default()
                    });

            pass.set_bind_group(0, &bind_group.0, &[]);
            pass.set_pipeline(init_pipeline);
            pass.dispatch_workgroups(
                camera.img_dims.x.div_ceil(8),
                camera.img_dims.y.div_ceil(8),
                1,
            );
        }
        Ok(())
    }
}

// pub fn setup() {

// }

// use bevy::prelude::*;
// use bevy_app_compute::prelude::*;

// use crate::{FragCamera, GameWorld};

// #[derive(TypePath)]
// pub struct SimpleShader;

// impl ComputeShader for SimpleShader {
//     fn shader() -> ShaderRef {
//         "shaders/raytrace-compiled.wgsl".into()
//     }
// }

// #[derive(Resource)]
// pub struct SimpleComputeWorker;

// impl ComputeWorker for SimpleComputeWorker {
//     fn build(world: &mut World) -> AppComputeWorker<Self> {
//         let game_world = world.resource::<GameWorld>().clone();
//         let frag_cam = world.resource::<FragCamera>().clone();
//         let worker = AppComputeWorkerBuilder::new(world)
//             .add_staging("accumulated_tex", &vec![0u32; (frag_cam.img_dims.x*frag_cam.img_dims.y) as _])
//             .add_uniform("cam", &frag_cam)
//             .add_storage("voxel_chunks", &game_world.voxel_chunks)
//             .add_storage("block_data", &game_world.block_data)
//             .add_pass::<SimpleShader>([frag_cam.img_dims.x as _, frag_cam.img_dims.y as _, 1], &["accumulated_tex", "cam", "voxel_chunks", "block_data"])
//             .build();

//         worker
//     }
// }

// pub fn test(
//     mut compute_worker: ResMut<AppComputeWorker<SimpleComputeWorker>>
// ) {
//     if !compute_worker.ready() {
//         return;
//     };
//     // dbg!(compute_worker.read_vec::<Vec<u32>>("accumulated_tex").len());

//     let mut buf = compute_worker.get_buffer("accumulated_tex").unwrap();

//     bevy::render::storage::ShaderStorageBuffer::from(buf.as_entire_buffer_binding());

//     let result: Vec<u32> = buf.as_entire_buffer_binding();
//     dbg!(&result[0..100]);
//     panic!();
//     // compute_worker.write_slice::<f32>("values", &[2., 3., 4., 5.]);

//     // println!("got {:?}", result)
// }

#[derive(Resource, ExtractResource, Clone)]
pub struct BeamReadbackBuffer {
    pub max_depth_buffer: Handle<ShaderStorageBuffer>,
}

pub struct BeamGpuReadbackPlugin;
impl Plugin for BeamGpuReadbackPlugin {
    fn build(&self, _app: &mut App) {}

    fn finish(&self, app: &mut App) {
        let render_app = app.sub_app_mut(RenderApp);
        render_app.init_resource::<BeamComputePipeline>().add_systems(
            Render,
            ((beam_prepare_bind_group)
                .in_set(RenderSet::PrepareBindGroups)
                // We don't need to recreate the bind group every frame
                .run_if(not(resource_exists::<BeamGpuBufferBindGroup>)), resize_cameras.after(prepare_bind_group)),

        );
        // Add the compute node as a top level node to the render graph
        // This means it will only execute once per frame
        render_app
            .world_mut()
            .resource_mut::<RenderGraph>()
            .add_node(BeamComputeNodeLabel, BeamComputeNode::default());
    }
}

#[derive(Resource)]
pub struct BeamGpuBufferBindGroup(pub BindGroup);

#[derive(Resource)]
pub struct BeamComputePipeline {
    layout: BindGroupLayout,
    pipeline: CachedComputePipelineId,
}

impl FromWorld for BeamComputePipeline {
    fn from_world(world: &mut World) -> Self {
        let render_device = world.resource::<RenderDevice>();
        let layout = render_device.create_bind_group_layout(
            Some("Beam Bind group layout compute"),
            &BindGroupLayoutEntries::sequential(
                ShaderStages::COMPUTE,
                (
                    storage_buffer::<Vec<u32>>(false),
                    uniform_buffer::<FragCamera>(false),
                    storage_buffer_read_only::<Vec<VoxelChunk>>(false),
                    storage_buffer_read_only::<Vec<MapDataPacked>>(false),
                    storage_buffer_read_only::<Vec<MapDataPacked>>(false),
                    storage_buffer_read_only::<Vec<MapDataPacked>>(false),
                    storage_buffer_read_only::<Vec<MapDataPacked>>(false),
                ),
            ),
        );
        let shader = world.load_asset("shaders/beam-compiled.wgsl");
        let pipeline_cache = world.resource::<PipelineCache>();
        let pipeline = pipeline_cache.queue_compute_pipeline(ComputePipelineDescriptor {
            label: Some("Beam optimizer".into()),
            layout: vec![layout.clone()],
            push_constant_ranges: Vec::new(),
            shader: shader.clone(),
            shader_defs: vec![ShaderDefVal::UInt("_CHUNK_SIZE".to_string(), CHUNK_SIZE as u32)],
            entry_point: "main".into(),
            zero_initialize_workgroup_memory: false,
        });
        Self { layout, pipeline }
    }
}

/// Label to identify the node in the render graph
#[derive(Debug, Hash, PartialEq, Eq, Clone, RenderLabel)]
struct BeamComputeNodeLabel;

/// The node that will execute the compute shader
#[derive(Default)]
struct BeamComputeNode {}
impl render_graph::Node for BeamComputeNode {
    fn run(
        &self,
        _graph: &mut render_graph::RenderGraphContext,
        render_context: &mut RenderContext,
        world: &World,
    ) -> Result<(), render_graph::NodeRunError> {
        if world.get_resource::<FragCamera>().is_none() {
            info!("Couldn't get frag camera, skipping compute pass.");
            return Ok(());
        }
        let pipeline_cache = world.resource::<PipelineCache>();
        let pipeline = world.resource::<BeamComputePipeline>();
        let bind_group = world.resource::<BeamGpuBufferBindGroup>();
        let camera = world.resource::<FragCamera>();


        if let Some(init_pipeline) = pipeline_cache.get_compute_pipeline(pipeline.pipeline) {
            let mut pass =
                render_context
                    .command_encoder()
                    .begin_compute_pass(&ComputePassDescriptor {
                        label: Some("Beam optimizer"),
                        ..default()
                    });

            pass.set_bind_group(0, &bind_group.0, &[]);
            pass.set_pipeline(init_pipeline);
            pass.dispatch_workgroups(
                (camera.img_dims.x + 16 - 1) / 16,
                (camera.img_dims.y + 16 - 1) / 16,
                1,
            );
        }
        Ok(())
    }
}