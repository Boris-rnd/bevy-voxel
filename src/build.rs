use bevy::prelude::*;

use crate::{world::World, Chunk};

pub fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    commands.spawn(MaterialMeshBundle {
        mesh: meshes.add(Cuboid::new(1., 1., 1.)),
        material: materials.add(Color::srgb_u8(100, 100, 100)),
        transform: Transform::default(),
        visibility: Visibility::Hidden,
        ..Default::default()
    }).insert(BuildPlaceholder);
    commands.insert_resource(World::new(0));
}

pub fn build(
    camera: Query<&Transform, With<Camera>>,
    mut chunks: Query<&mut Transform, (Without<Camera>, With<Chunk>)>,
) {
    let camera = camera.single();
    for i in 0..100 {
        let ray_pos = camera.forward()*i as f32;
        for chunk in chunks.iter_mut() {
            
        }

    }
}

#[derive(Component)]
pub struct BuildPlaceholder;