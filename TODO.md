# TODO

- [X] Implement frustum culling
- [X] Separate chunk meshes from chunk data
  - Thus make chunks *actually* 16x256x16, and separate meshes into the current 16^3
- [X] Generate meshes closer to the player first
- [ ] There's some issue ONLY in debug mode where a chunk is empty (& sometimes a floating block is there too)
- [ ] Animated water texture (requires separate 'liquid' mesh to animate? Also probably a *.meta file?)
  - Make atlas generate separate face data (w/ colours n all that)?
- [ ] Better transparency; glass/water still has cutoffs
  - [ ] Probably needs different winding
  - [ ] MC also has 4 tris per face for water, both cw & ccw (excl. bottom)
- [ ] Move worldgen onto a separate thread
- [ ] Add 'regions', containing 32^2 chunks each

## Backburner

- [ ] Fix mu issues or move to imgui
  - [ ] When resizing window, mu panels will be cut off unless they're moved to the top left
- [?] Remove chunk from remesh queue when unloading if it's in there (hash set?)
