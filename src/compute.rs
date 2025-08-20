pub fn compute_update(mut compute_worker: ResMut<AppComputeWorker<SimpleComputeWorker>>) {
    if !compute_worker.ready() {
        return;
    };
    // let result: Vec<f32> = compute_worker.read_vec("values");
    
    // compute_worker.write_slice("values", &[2.0f32, 3., 4., 5.]);

    // println!("got {:?}", result)
}
use super::*;

#[derive(TypePath)]
pub struct SimpleShader;

impl ComputeShader for SimpleShader {
    fn shader() -> ShaderRef {
        "shaders/simple.wgsl".into()
    }
}
#[derive(Resource)]
pub struct SimpleComputeWorker;

impl ComputeWorker for SimpleComputeWorker {
    fn build(world: &mut World) -> AppComputeWorker<Self> {
        let worker = AppComputeWorkerBuilder::new(world)
            .add_uniform("uni", &5.)
            .add_staging("accumulated_tex", &[0u32; 800*600])
            .add_pass::<SimpleShader>([4, 1, 1], &["uni", "accumulated_tex"])
            .build();

        worker
    }
}
