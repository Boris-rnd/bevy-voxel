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

valgrind --tool=callgrind --callgrind-out-file=callgrind.out --collect-jumps=yes --simulate-cache=yes

## Features

- 3D Raytracing with bouncing (with some quirks)
- Sparse voxel 64-tree
- A python script to import other .wgsl shaders (see assets/shaders/compile.py) (with auto-reload and watch for file changes)
- .vox parsing & loading (not fully implemented)
- 60 fps on a 1080p screen on my laptop for all of the scenes (but some graphical artifacts)

## Optimisations

BEAM (see Douglas' video) => Basically a lower rendering to get an approximate start distance for every ray, then reuse the previous frame's hit position to continue the ray from there, with higher resolution
I did this optimisation with multiple passes (which you can tweak easily). Do note that the beam max distance is random and so there are some graphical artifacts
The Sparse voxel 64-tree uses some bitwise optimisations to speed up the traversal, and optimise memory utilization
(Don't store empty blocks, but store additionnal block data, which needed to transform a bit index (from the 64-bits representing a chunk) to get the block data inside the chunk (which could be a leaf node or another octree = chunkception !))
Accumulate frame data when not moving (no speed up but makes some scenes look cool)

## TODO

Fix the bouncing rays making everything very dark
Make the sparse voxel tree more efficient (It will never be enough)
Refactor all of the code because it's a mess and a lot of stuff is broken
Update everything
In a perfect future I would also like to support some physics simulations inside the engine like fluids (like Grant Kot does in some videos)

![Castle preview](preview_castle_vox.png)
