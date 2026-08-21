# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A locally-run, Star Wars Battlefront II (2005)–style class-based conquest shooter built in Godot 4 (GDScript), aimed eventually at seamless ground-to-space combat (the cancelled Battlefront III feature). Currently a vertical slice: soldier classes, AI bots, a conquest game mode, and two AI-usable vehicles, all on one grey-box map. See README.md for controls and ROADMAP.md for what's built vs. planned — ROADMAP.md's "Architecture recap" section and its per-phase notes double as a running log of non-obvious bugs found during playtesting; read it before touching vehicle or AI code.

## Commands

Run natively: `godot --path .` (from repo root; `godot` must be on PATH, e.g. `brew install --cask godot` on macOS). No build step — GDScript is interpreted, scenes/scripts are read directly.

Verify a change compiles cleanly (fast, catches script/scene parse errors):
```
godot --headless --path . --quit
```
The first time new `class_name` scripts are added in a session, run `godot --headless --editor --quit` once instead — this rebuilds the global class-name cache that `--quit` alone won't refresh, and without it you'll see spurious "Could not find type X" errors.

Verify a change actually *runs* correctly (not just parses) — there's no automated test suite, so this headless-live-run pattern is the substitute. Run the real match scene in the background for tens of seconds and grep the log for errors:
```
(godot --headless --path . scenes/core/Main.tscn > /tmp/run.log 2>&1 & echo $! > /tmp/run.pid)
sleep 30 && kill $(cat /tmp/run.pid)
grep -i error /tmp/run.log
```
This boots the full match (bots spawn, fight, capture points, drive vehicles) with no rendering — cheap and effective for catching runtime bugs (an infinite loop, a navigation deadlock, unreset vehicle controls, and an AI state oscillation were all found this way). Absence of `ERROR` output is meaningful; absence of *any* output is not — a hung/looping process produces no output either, so if you add periodic diagnostic prints while investigating something, confirm they keep advancing, not just that nothing errored.

Web export, useful for visually testing in a browser when a native window isn't inspectable (e.g. from an agent sandbox):
```
tools/export_web.sh [debug|release]   # rebuilds build/web/
tools/serve_web.sh [port]              # serves it over plain HTTP (port defaults to 8060)
tools/watch_web.sh                     # export + auto re-export on file change (needs fswatch)
```
Requires Godot's export templates installed once (`~/Library/Application Support/Godot/export_templates/<version>/`, downloaded from the matching GitHub release — not bundled with the `brew install --cask godot` editor). This is a dev/testing aid only, not a way to hand the game to someone without Godot installed.

No lint step and no automated test suite exist in this project.

## Architecture

**The core pattern: driven things vs. things that drive them.** `Unit.gd` (soldiers) and `Vehicle.gd` (vehicles) never read input directly — every physics frame they just read public fields (`move_input`, `look_direction`, `fire_held` for `Unit`; `move_input`, `fire_held`, `turret_look_direction`, `turret_fire_held` for `Vehicle`) and act on them. Two separate "intent producers" write those fields: `PlayerInput.gd` (reads the Input map) and `AIBrain.gd` (a small staggered-decision state machine). Both attach as a sibling child of the `Unit` they drive. This is why bots and the player share identical movement/combat behavior, and it's the seam a networked input source would hook into later — new input-reading code belongs in a producer like these, never in `Unit.gd`/`Vehicle.gd`/`WeaponHandler.gd`/`Health.gd`.

**Vehicles extend the same pattern via possession, not inheritance.** `VehicleSeat.gd` (an `Area3D` per seat) tracks who's occupying it; entering swaps which intent-producer is currently writing the *vehicle's* fields instead of the soldier's. `PlayerInput`/`AIBrain` both implement `force_exit_vehicle(instigator, eject_damage)` so `VehicleSeat` can eject an occupant symmetrically regardless of who's driving. Whenever a new way to stop driving/gunning a vehicle gets added, it should route through `VehicleSeat.exit_seat()` — it's the one chokepoint every dismount path already goes through, and it's responsible for zeroing the vehicle's intent fields so an abandoned vehicle doesn't keep moving/firing forever (a real bug found via playtesting).

**Content is data, not code.** `WeaponData`/`ClassData`/`FactionData` (`scripts/data/`) and `VehicleData` (`scripts/vehicle/VehicleData.gd`) are `Resource` subclasses saved as `.tres` under `resources/`. Adding a class, weapon, or vehicle variant should almost always mean authoring a new `.tres`, not new GDScript.

**Autoloads own cross-cutting state**, not any one scene: `MatchState` (tickets, the command-post registry, win condition — scoped to the whole match, not per-map, so a future space-layer's command posts register into the exact same list and share one win condition automatically), `EventBus` (a plain signal bus so unrelated systems like HUD/AI don't hold direct references to each other), `GameManager` (top-level game state, local player faction).

**AI decision-making is timer-staggered, not per-frame**, in both `AIBrain.gd`'s foot state machine and its vehicle driving/gunning state machine — a randomized 0.35–0.6s interval per bot for target/objective selection and line-of-sight checks (movement/aim ticking still runs every physics frame). This is the main lever keeping many simultaneous bots cheap; new expensive per-bot scans belong behind that same decision timer, not in a per-frame path.

**Physics layers** (see `project.godot`'s `[layer_names]`): 1=world, 2=units, 3=hurtbox (unused), 4=projectile (unused), 5=capture_zone. Soldiers (`Unit`, layer 2, mask 1) don't collide with each other, but vehicles (layer 2+1, mask 1) *are* solid to soldiers and to weapon-fire raycasts (which mask world+units) — this asymmetry is intentional, not a bug.

**Godot-specific gotchas that have bitten this project before:**
- Child nodes' `_ready()` runs before their parent's. A node that self-initializes in its own `_ready()` can race a parent's setup that hasn't run yet (e.g. a navmesh bake) — `call_deferred()` the risky part instead.
- `queue_free()` doesn't reduce `get_child_count()` until end-of-frame — a `while count() > N: queue_free(get_child(0))` loop spins forever the instant it's actually needed. Use `if`, not `while`, when only one eviction is ever expected per call.
- `NavigationAgent3D`-driven movement should stop based on `is_navigation_finished()` alone, not an additional manual "is the next waypoint close" distance check — a short path's first waypoint can already be within such a threshold, permanently zeroing movement before the agent's own arrival logic ever advances past it.

## Workflow this project has been using

One git branch per feature/fix, verified (headless parse + headless live-run, plus a manual/browser check when the change is visual or needs real input) before merging back to `main` with `--ff-only`, then the branch is deleted. Commit messages for bugs found via live testing describe what was actually observed, not just the first guessed cause — the initial hypothesis has repeatedly turned out wrong, and the real diagnosis is what's worth preserving.
