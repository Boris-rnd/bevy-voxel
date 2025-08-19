# Intro

This is a very simple voxel engine WIP built in Rust + Bevy only for educational purposes
I used a bit of AI to do the job but I think it's trash
Currently uses a Sparse voxel 64-tree with raycasting
To run: cargo r
To update shaders (auto-reload and watch for file changes):
```sh
python assets/shaders/compile.py assets/shaders/raytrace.wgsl
```

Then you can just 
```sh
clear && cargo r
```

