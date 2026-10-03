# Superseding visual direction: stylized-realistic 3D

The user rejected the 2D map. They explicitly selected stylized realism for a modern 3D game. The 2D rendering plan in `brief.md` is superseded. The verified simulation stays; a 2D build is not the requested delivery.

## Required experience

Continuous camera movement from a person-scale close view to the whole valley. Real perspective, terrain relief, orbit, tilt, panning, and smooth zoom. Detailed, readable people and architecture at close range. Natural materials, animated characters, water, directional shadows, atmosphere, and a coherent landscape. Do not substitute a 3D board of boxes for the requested visual quality.

The existing two villages, 24 people, finite drought, two miracles, causal histories, deterministic simulation, and isolated aka deployment remain unchanged. BW2 and Korri remain untouched.

## Integration contract

The existing simulation plane remains 1000 by 640. Render it as X/Z meters using `(sim.x * 0.1 - 50, sim.y * 0.1 - 32)`. People are about 1.7 meters tall. All render positions take Y from `terrain.height_at(Vector2(world_x, world_z))`. Model state and RNG remain independent of camera, animation, and graphics.

`game/terrain.gd` extends Node3D. It builds a valley about 240 by 180 meters with higher surrounding hills, a depressed winding watercourse, village clearings centered at (-26, 2) and (26, 2), the shrine at (0, -4), and a common spring at (0, 8.5). Expose pure `height_at(Vector2) -> float`, `update_resources(villages: Array, well_water: float)`, and `set_wetness(point: Vector2, strength: float)` if supported. All terrain-generated meshes stay below this node. No scene/clock/simulation mutation from terrain.

Keep the actual travel areas clear of solid architecture. Home positions are within 7.6m of a village center. Actual crop jobs are 2.7 to 5.7 meters north of the village centers. Larger southern fields also provide landscape context. Homes/large structures therefore belong on the outer north side or outside the main movement corridors. Direct travel remains a simulation limit; dressing must not make wall-crossing the normal visible behavior.

The camera and world Control remain parent-owned. Terrain and models plug into a SubViewport with a real Camera3D. World interaction uses camera rays, not top-down screen-coordinate guesses. HUD controls remain reachable at the existing size ladder.

Rendering targets Godot 4.6.1 Forward+ on aka's RX 7900 XT. Verify this actual path rather than assume the earlier Compatibility renderer check covers it. Limit expensive effects when they harm person-scale readability or frame time. A low-detail mode is not the default art target.

## Verification additions

Prove close-up, village, and landscape camera positions through actual mouse input on aka. Check picking and miracle placement at different zooms, terrain clearance, and resize behavior. Capture real close-up and overview images and a gameplay recording that visibly moves between those scales. Rerun seeded behavior tests and actual input/render/audio/restart acceptance after the 3D replacement.
