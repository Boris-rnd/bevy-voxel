// use bevy::{input::mouse::{MouseMotion, MouseScrollUnit, MouseWheel}, prelude::*};

// pub fn camera_movement(
//     mut camera: Query<(&mut Transform,
//         &PanOrbitSettings,
//         &mut PanOrbitState,), With<Camera>>,
//     kb: Res<ButtonInput<KeyCode>>,
//     mouse: Res<ButtonInput<MouseButton>>,
//     mut scroll: EventReader<MouseWheel>,
//     mut mouse_mov: EventReader<MouseMotion>,
// ) {
//     let (mut camera, settings, mut state) = camera.single_mut();
//     if kb.pressed(KeyCode::KeyZ) {
//         let forward = camera.forward().as_vec3();
//         state.center += forward;
//     }
//     if kb.pressed(KeyCode::KeyS) {
//         let back = camera.back().as_vec3();
//         state.center += back;
//     }
//     if kb.pressed(KeyCode::KeyQ) {
//         let left = camera.left().as_vec3();
//         state.center += left;
//     }
//     if kb.pressed(KeyCode::KeyD) {
//         let right = camera.right().as_vec3();
//         state.center += right;
//     }
//     let total_motion: Vec2 = mouse_mov.read()
//     .map(|ev| ev.delta).sum();

//     let total_orbit = total_motion * settings.orbit_sensitivity;
//     if total_orbit != Vec2::ZERO && mouse.pressed(MouseButton::Right) {
//         state.yaw -= total_orbit.x;
//         state.pitch -= total_orbit.y;
//         // wrap around, to stay between +- 180 degrees
//         if state.yaw > PI {
//             state.yaw -= TAU; // 2 * PI
//         }
//         if state.yaw < -PI {
//             state.yaw += TAU; // 2 * PI
//         }
//         if state.pitch > PI {
//             state.pitch -= TAU; // 2 * PI
//         }
//         if state.pitch < -PI {
//             state.pitch += TAU; // 2 * PI
//         }
//     }
//     let mut total_scroll_lines = Vec2::ZERO;
//     let mut total_scroll_pixels = Vec2::ZERO;
//     for ev in scroll.read() {
//         match ev.unit {
//             MouseScrollUnit::Line => {
//                 total_scroll_lines.x += ev.x;
//                 total_scroll_lines.y -= ev.y;
//             }
//             MouseScrollUnit::Pixel => {
//                 total_scroll_pixels.x += ev.x;
//                 total_scroll_pixels.y -= ev.y;
//             }
//         }
//     }
//     let mut total_zoom = -(total_scroll_lines
//         * settings.scroll_line_sensitivity * settings.zoom_sensitivity);
//     total_zoom -= total_scroll_pixels
//         * settings.scroll_pixel_sensitivity * settings.zoom_sensitivity;

//     if total_zoom != Vec2::ZERO {
//         // in order for zoom to feel intuitive,
//         // everything needs to be exponential
//         // (done via multiplication)
//         // not linear
//         // (done via addition)

//         // so we compute the exponential of our
//         // accumulated value and multiply by that
//         state.radius *= (-total_zoom.y).exp();
//     }

//     // YXZ Euler Rotation performs yaw/pitch/roll.
//     camera.rotation =
//         Quat::from_euler(EulerRot::YXZ, state.yaw, state.pitch, 0.0);
//     // To position the camera, get the backward direction vector
//     // and place the camera at the desired radius from the center.
//     camera.translation = state.center + camera.back() * state.radius;
//     // // Reverse Y (Bevy's Worldspace coordinate system is Y-Up,
//     // // but events are in window/ui coordinates, which are Y-Down)
//     // total_motion.y = -total_motion.y;

//     // let sensitivity = -0.005; // Adjust as needed
//     // let pitch = total_motion.y * sensitivity;
//     // let yaw = total_motion.x * sensitivity;

//     // camera.rotation *= Quat::from_axis_angle(Vec3::Y, yaw);
//     // camera.rotation *= Quat::from_axis_angle(Vec3::X, pitch);

// }

// #[derive(Bundle, Default)]
// pub struct PanOrbitCameraBundle {
//     pub camera: Camera3dBundle,
//     pub state: PanOrbitState,
//     pub settings: PanOrbitSettings,
// }

// // The internal state of the pan-orbit controller
// #[derive(Component)]
// pub struct PanOrbitState {
//     pub center: Vec3,
//     pub radius: f32,
//     pub upside_down: bool,
//     pub pitch: f32,
//     pub yaw: f32,
// }

// /// The configuration of the pan-orbit controller
// #[derive(Component)]
// pub struct PanOrbitSettings {
//     /// World units per pixel of mouse motion
//     pub pan_sensitivity: f32,
//     /// Radians per pixel of mouse motion
//     pub orbit_sensitivity: f32,
//     /// Exponent per pixel of mouse motion
//     pub zoom_sensitivity: f32,
//     /// What action is bound to the scroll wheel?
//     pub scroll_action: Option<PanOrbitAction>,
//     /// For devices with a notched scroll wheel, like desktop mice
//     pub scroll_line_sensitivity: f32,
//     /// For devices with smooth scrolling, like touchpads
//     pub scroll_pixel_sensitivity: f32,
// }

// #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
// pub enum PanOrbitAction {
//     Pan,
//     Orbit,
//     Zoom,
// }

// impl Default for PanOrbitState {
//     fn default() -> Self {
//         PanOrbitState {
//             center: Vec3::ZERO,
//             radius: 1.0,
//             upside_down: false,
//             pitch: 0.0,
//             yaw: 0.0,
//         }
//     }
// }

// impl Default for PanOrbitSettings {
//     fn default() -> Self {
//         PanOrbitSettings {
//             pan_sensitivity: 0.001, // 1000 pixels per world unit
//             orbit_sensitivity: 0.1f32.to_radians(), // 0.1 degree per pixel
//             zoom_sensitivity: 0.01,
//             scroll_action: Some(PanOrbitAction::Zoom),
//             scroll_line_sensitivity: 16.0, // 1 "line" == 16 "pixels of motion"
//             scroll_pixel_sensitivity: 1.0,
//         }
//     }
// }

// use std::f32::consts::{PI, TAU};

// // pub fn pan_orbit_camera(
// //     kbd: Res<ButtonInput<KeyCode>>,
// //     mut evr_motion: EventReader<MouseMotion>,
// //     mut evr_scroll: EventReader<MouseWheel>,
// //     mut q_camera: Query<(
// //         &PanOrbitSettings,
// //         &mut PanOrbitState,
// //         &mut Transform,
// //     )>,
// // ) {
// //     // First, accumulate the total amount of
// //     // mouse motion and scroll, from all pending events:
// //     let mut total_motion: Vec2 = evr_motion.read()
// //         .map(|ev| ev.delta).sum();

// //     // Reverse Y (Bevy's Worldspace coordinate system is Y-Up,
// //     // but events are in window/ui coordinates, which are Y-Down)
// //     total_motion.y = -total_motion.y;

// //     let mut total_scroll_lines = Vec2::ZERO;
// //     let mut total_scroll_pixels = Vec2::ZERO;
// //     for ev in evr_scroll.read() {
// //         match ev.unit {
// //             MouseScrollUnit::Line => {
// //                 total_scroll_lines.x += ev.x;
// //                 total_scroll_lines.y -= ev.y;
// //             }
// //             MouseScrollUnit::Pixel => {
// //                 total_scroll_pixels.x += ev.x;
// //                 total_scroll_pixels.y -= ev.y;
// //             }
// //         }
// //     }

// //     for (settings, mut state, mut transform) in &mut q_camera {
// //         // Check how much of each thing we need to apply.
// //         // Accumulate values from motion and scroll,
// //         // based on our configuration settings.

// //         let mut total_orbit = Vec2::ZERO;
// //         if settings.orbit_key.map(|key| kbd.pressed(key)).unwrap_or(false) {
// //             total_orbit -= total_motion * settings.orbit_sensitivity;
// //         }
// //         if settings.scroll_action == Some(PanOrbitAction::Orbit) {
// //             total_orbit -= total_scroll_lines
// //                 * settings.scroll_line_sensitivity * settings.orbit_sensitivity;
// //             total_orbit -= total_scroll_pixels
// //                 * settings.scroll_pixel_sensitivity * settings.orbit_sensitivity;
// //         }

// //         let mut total_zoom = Vec2::ZERO;
// //         if settings.zoom_key.map(|key| kbd.pressed(key)).unwrap_or(false) {
// //             total_zoom -= total_motion * settings.zoom_sensitivity;
// //         }
// //         if settings.scroll_action == Some(PanOrbitAction::Zoom) {
// //             total_zoom -= total_scroll_lines
// //                 * settings.scroll_line_sensitivity * settings.zoom_sensitivity;
// //             total_zoom -= total_scroll_pixels
// //                 * settings.scroll_pixel_sensitivity * settings.zoom_sensitivity;
// //         }

// //         // Upon starting a new orbit maneuver (key is just pressed),
// //         // check if we are starting it upside-down
// //         if settings.orbit_key.map(|key| kbd.just_pressed(key)).unwrap_or(false) {
// //             state.upside_down = state.pitch < -FRAC_PI_2 || state.pitch > FRAC_PI_2;
// //         }

// //         // If we are upside down, reverse the X orbiting
// //         if state.upside_down {
// //             total_orbit.x = -total_orbit.x;
// //         }

// //         // Now we can actually do the things!

// //         let mut any = false;

// //         // To ZOOM, we need to multiply our radius.
// //         if total_zoom != Vec2::ZERO {
// //             any = true;
// //             // in order for zoom to feel intuitive,
// //             // everything needs to be exponential
// //             // (done via multiplication)
// //             // not linear
// //             // (done via addition)

// //             // so we compute the exponential of our
// //             // accumulated value and multiply by that
// //             state.radius *= (-total_zoom.y).exp();
// //         }

// //         // To ORBIT, we change our pitch and yaw values

// //         // To PAN, we can get the UP and RIGHT direction
// //         // vectors from the camera's transform, and use
// //         // them to move the center point. Multiply by the
// //         // radius to make the pan adapt to the current zoom.
// //         if total_pan != Vec2::ZERO {
// //             any = true;
// //             let radius = state.radius;
// //             state.center += transform.right() * total_pan.x * radius;
// //             state.center += transform.up() * total_pan.y * radius;
// //         }

// //         // Finally, compute the new camera transform.
// //         // (if we changed anything, or if the pan-orbit
// //         // controller was just added and thus we are running
// //         // for the first time and need to initialize)
// //         if any || state.is_added() {
// //             // YXZ Euler Rotation performs yaw/pitch/roll.
// //             transform.rotation =
// //                 Quat::from_euler(EulerRot::YXZ, state.yaw, state.pitch, 0.0);
// //             // To position the camera, get the backward direction vector
// //             // and place the camera at the desired radius from the center.
// //             transform.translation = state.center + transform.back() * state.radius;
// //         }
// //     }
// // }

use bevy::render::extract_resource::ExtractResource;

use super::*;
// #[repr(C)]
#[derive(ShaderType, Reflect, Debug, Clone, Resource, Default, ExtractResource, Asset)]
pub struct FragCamera {
    pub center: Vec3,
    pub direction: Vec3,
    pub fov: f32,
    pub root_max_depth: u32,
    pub accumulated_frames: u32,
    pub img_dims: UVec2,
}

// #[derive(Resource)]
// pub struct SharedFragCamera(pub Handle<FragCamera>);

impl FragCamera {
    pub fn new(center: Vec3, direction: Vec3, fov: f32, root_max_depth: u32, img_dims: UVec2) -> Self {
        Self {
            center,
            direction,
            fov,
            root_max_depth,
            accumulated_frames: 0,
            img_dims,
            ..Default::default()
        }
    }
}
