# Roadmap

Current state: a playable vertical slice — Trooper/Heavy classes, AI bots, one grey-box conquest map, full capture/ticket/win-condition logic. Everything below is designed to slot into the existing architecture without rewriting it. Rough order reflects dependency, not necessarily priority — reorder freely.

## Architecture recap (read this before extending)

- **Data-driven balance**: `WeaponData` / `ClassData` / `FactionData` (`scripts/data/`) are `Resource` subclasses saved as `.tres` under `resources/`. A new class or weapon is almost always a new `.tres` file, not new code.
- **Player and AI are the same code path**: `Unit.gd` (`scripts/unit/Unit.gd`) reads `move_input` / `look_direction` / `sprint_held` / `fire_held` / etc. every physics frame and does movement + firing. `PlayerInput.gd` fills those fields from the keyboard/mouse; `AIBrain.gd` fills them from a small state machine. Neither Unit.gd nor WeaponHandler.gd/Health.gd know or care which one is driving. **Any new input source (a vehicle seat, a networked client) should follow this same pattern**: write the intent fields, don't touch movement/combat code.
- **Combat**: hitscan blasters do instant raycast damage plus a purely visual tracer (`Bolt.gd`); explosives are real physics projectiles (`Projectile.gd`) with splash damage. Both look up damage targets via `collider.get_health()` — anything that should be shootable needs a `get_health() -> Health` method (Unit.gd already has one; vehicles will need the same).
- **Match state**: `MatchState` (autoload) owns tickets and the command-post registry across the *whole match*, not per-map. `CommandPost.gd` registers itself into `MatchState.command_posts` on `_ready()`. This is deliberate: when a space layer exists, its command posts register into the exact same list, so ground and space share one win condition automatically.

## Phase 1 — Round out the soldier classes

- Add Sniper (`WeaponData` with high damage/low fire-rate/long range, maybe a scope-zoom FOV on `aim`), Engineer (repair/mines/ammo-resupply — needs a new small "gadget" concept, e.g. an `@export var gadget: PackedScene` on `ClassData`), Officer (buff aura — a `Node` component that boosts nearby allies' `regen_per_second` via `Health`).
- Wire up weapon *switching* (primary/secondary), not just one equipped weapon — `switch_weapon` input action already exists but isn't consumed yet. `WeaponHandler` would need a second slot and an `equip_slot(index)` call from `PlayerInput`/`AIBrain`.
- Thermal detonator as a throwable using the existing `Projectile.gd` (it already supports arcing + splash).

## Phase 2 — Vehicles (done: speeder bike + walker, player- and AI-usable)

Built: `Vehicle.gd`/`VehicleSeat.gd`/`VehicleData.gd`/`VehicleHealth.gd` (`scripts/vehicle/`), reusing `Health`/`WeaponHandler` exactly as `Unit.gd` does. Seats possess the occupant's `PlayerInput` (or `AIBrain` — see below) the same way `PlayerInput`/`AIBrain` drive `Unit` — enter/exit mirrors `Unit`'s own hide/disable pattern, so the soldier is paused not destroyed. Two vehicles live at `scenes/vehicles/`: the speeder bike (single seat, fast/fragile hover) and the AT-ST-style walker (driver + independently-aimed gunner turret, slow/armored, grounded). Vehicles carry a regenerating shield in front of health. Playtesting caught and fixed two real bugs early on worth remembering: vehicle `CameraRig`s auto-activating on spawn (fixed via `start_active`/`activate()`), and the walker's two seat triggers fully overlapping so the gunner seat was unreachable (fixed by spatially separating them).

**AI driving and gunner crewing are done too.** `AIBrain.gd` seeks out, boards, drives/guns, fights from, and dismounts vehicles using the same staggered-decision shape as foot combat — `VehicleSeat.occupy()`/`force_exit_vehicle()` already accepted any `Node` in the "player_input" role, so this needed zero changes to the shipped player-possession contract. Live/headless playtesting (not design review alone) caught several real bugs worth remembering if this code gets touched again:
- Godot calls children's `_ready()` before their parent's — `VehicleSpawner` spawning in its own `_ready()` raced `ConquestMode`'s navmesh bake, permanently carving a hole where the vehicle sat. Fixed by deferring the spawn one frame.
- The shared foot-navigation helper (`_tick_navigate`, also used for capturing command posts) zeroed movement whenever the *next path waypoint* was close, not just the final destination — a short vehicle-seek path can start with its first waypoint already that close, permanently deadlocking the bot at zero velocity. Only `is_navigation_finished()` should decide "have we arrived."
- AI vehicle steering had the turn direction backwards — confirmed by watching a bot drive straight off the map and free-fall forever (`pos.y` reaching -287) before the sign was fixed. Verify steering sign changes live, don't trust the math on paper.
- Nothing ever reset `Vehicle.move_input`/`fire_held`/`turret_fire_held` when a driver/gunner exited, so an abandoned vehicle just kept driving/firing at its last command forever. Fixed at `VehicleSeat.exit_seat()` — the one chokepoint every dismount path (player/AI, voluntary/forced) already routes through.
- The engage decision re-scanned for a visible enemy from scratch on every staggered tick, even while already validly fighting one. A single momentary line-of-sight miss (common at range) would drop the target, drive forward one tick, then reacquire and stop again — oscillating rapidly ("inching forward" while never actually committing to the fight). Fixed by sticking with a still-valid target instead of re-rolling every tick.
- The vehicle movement model is forward-only (no reverse or strafe), so true kiting/circling isn't achievable without a bigger movement-model change — "stop closing once already in comfortable firing range" is the closest approximation actually achievable today.

Also added, independent of any single bug: map-boundary steering (any AI vehicle steering call overrides toward map center past a safety margin) and basic forward obstacle avoidance — both live in the shared `_compute_steer_throttle` in `AIBrain.gd`.

**Remaining vehicle work, not yet built:**
- Direct seat-to-seat swap (driver ↔ gunner) without exiting first — currently `interact` while possessed always exits; confirmed acceptable UX for now, but a small addition to `VehicleSeat`/`PlayerInput` if wanted later.
- True kiting/circling combat AI — needs reverse/strafe support added to `Vehicle.gd`'s movement model first, a bigger change than the AI logic alone.
- More vehicle types as needed.

## Phase 3 — Flight and space combat

- `AtmosphericFlightController` for in-map fighters/speeders (banking, throttle, altitude).
- A `SpaceZone` scene: same `ConquestMode`-style root, but flight-only (no ground, no gravity), positioned at a large Y offset from the ground map so both can be loaded simultaneously without coordinate precision issues.
- Space `CommandPost`s (subsystem objectives — shields, engines, hangar) register into the same shared `MatchState.command_posts` list ground posts use. No changes needed to `MatchState` itself.
- Capital ship interiors: a hangar `NavigationRegion3D` sized like the ground map's, entered by flying a fighter into a landing-bay trigger volume.
- **Troop transport/dropship** as a natural vehicle type here: the original BF2's AI transports landed at a friendly command post, picked up soldiers, then flew to and landed at an enemy post to deploy them — effectively a live preview of the flight-corridor mechanism above. Reuses the same `Vehicle`/`VehicleSeat` architecture from Phase 2 (multiple passenger seats, no weapon needed) plus whatever `AtmosphericFlightController`/`SpaceFlightController` this phase adds.

## Phase 4 — Seamless ground↔space transition (the signature feature)

- A flight corridor trigger volume near the ground map's upper bound. A flight vehicle crossing it swaps `AtmosphericFlightController` → `SpaceFlightController` (same seat-possession pattern from Phase 2) and cross-fades `WorldEnvironment`/skybox.
- Because `MatchState` is already match-scoped rather than map-scoped, and command posts already register into one shared list regardless of which scene they live in, this phase is mostly about the *flight/rendering* transition, not the match-state plumbing — that part already works.
- Verify: capturing every space CP should be able to end the match exactly like capturing every ground CP does today (`MatchState._apply_bleed_tick`'s all-posts-owned check already treats them identically).

## Phase 5 — Hero units, polish, audio, art

- Hero units as a third `ClassData`-like tier with much higher stats and a limited-use special ability — could reuse `ClassData` plus a `hero_only: bool` flag and a kill-count gate before it's selectable.
- Swap grey-box primitives for real models/animations — nothing in the mechanics layer should need to change (`MeshInstance3D` swaps are purely visual).
- Sound: hook into existing signals (`WeaponHandler.fired`, `Health.damaged`, `EventBus.command_post_captured`, etc.) rather than adding new event plumbing.
- Basic settings menu (sensitivity, key rebinding via the existing Input Map), main menu / map select in front of `Main.tscn`.

## Explicitly deferred (not currently planned)

- Networked multiplayer — the input-intent architecture is deliberately shaped so it *could* be added later (swap `PlayerInput` for a networked source per Unit), but no netcode exists yet and wasn't in scope for this pass.
