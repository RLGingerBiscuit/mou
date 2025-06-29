# TODO

- [X] Implement frustum culling
- [X] Separate chunk meshes from chunk data
  - Thus make chunks *actually* 16x256x16, and separate meshes into the current 16^3
- [X] Generate meshes closer to the player first
- [ ] There's a rare issue at larger render distances where a chunk sometimes isn't meshed properly
- [ ] Animated water texture (requires separate 'liquid' mesh to animate? Also probably a *.meta file?)
  - Make atlas generate separate face data (w/ colours n all that)?
- [X] Better transparency; glass/water still has cutoffs
  - [X] Probably needs different winding (it was just culling being disabled ofc)
  - [X] MC also has 4 tris per face for water, both cw & ccw (excl. bottom & connecting faces)
- [X] Setup profiling (tiny wrapper around spall for easy debug/release switching)
- [X] "world sort messages" is causing massive slowdowns due to the stack getting massive somehow
  - Demeshing calls weren't being guarded, so were added every frame until they were demeshed
- [ ] The frustum culling code needs a look at; sometimes chunks can be culled when in view
- [ ] Add 'regions', containing 32^2 chunks each
- [ ] Move worldgen onto a separate thread

## Backburner

- [ ] Fix mu issues or move to imgui
  - [ ] When resizing window, mu panels will be cut off unless they're moved to the top left
- [?] Remove chunk from remesh queue when unloading if it's in there (hash set?)
