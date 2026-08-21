# Roadmap

Current state: a playable vertical slice — five soldier classes (Trooper/Heavy/Sniper/Engineer/Officer), AI bots, one grey-box conquest map, full capture/ticket/win-condition logic, plus player-flyable/AI-dogfighting starfighters. Everything below is designed to slot into the existing architecture without rewriting it. Rough order reflects dependency, not necessarily priority — reorder freely.

## Architecture recap (read this before extending)

- **Data-driven balance**: `WeaponData` / `ClassData` / `FactionData` (`scripts/data/`) are `Resource` subclasses saved as `.tres` under `resources/`. A new class or weapon is almost always a new `.tres` file, not new code.
- **Player and AI are the same code path**: `Unit.gd` (`scripts/unit/Unit.gd`) reads `move_input` / `look_direction` / `sprint_held` / `fire_held` / etc. every physics frame and does movement + firing. `PlayerInput.gd` fills those fields from the keyboard/mouse; `AIBrain.gd` fills them from a small state machine. Neither Unit.gd nor WeaponHandler.gd/Health.gd know or care which one is driving. **Any new input source (a vehicle seat, a networked client) should follow this same pattern**: write the intent fields, don't touch movement/combat code.
- **Combat**: hitscan blasters do instant raycast damage plus a purely visual tracer (`Bolt.gd`); explosives are real physics projectiles (`Projectile.gd`) with splash damage. Both look up damage targets via `collider.get_health()` — anything that should be shootable needs a `get_health() -> Health` method (Unit.gd already has one; vehicles will need the same).
- **Match state**: `MatchState` (autoload) owns tickets and the command-post registry across the *whole match*, not per-map. `CommandPost.gd` registers itself into `MatchState.command_posts` on `_ready()`. This is deliberate: when a space layer exists, its command posts register into the exact same list, so ground and space share one win condition automatically.

## Phase 1 — Round out the soldier classes (done)

Sniper (high damage/low fire-rate/long range `WeaponData`, plus a real scope-zoom via a per-class `ClassData.aim_fov` — `CameraRig`'s aim FOV, previously a hardcoded constant, is now settable), Engineer (a repair tool as its *secondary* weapon rather than a bespoke gadget system — a new `WeaponData.FireMode.HEAL` reuses the exact same raycast `_fire_hitscan` already used, just calling `Health.heal()` instead of `apply_damage()`; repairs vehicles too for free, since they share the unit collision layer and already expose `get_health()`), Officer (a buff aura — `ClassData.class_ability: PackedScene`, a generic new extension point instantiated in `apply_class()`, currently only used for `OfficerAura.gd`). Weapon switching (primary/secondary, the previously-dead `switch_weapon` input action) and a thermal detonator throwable (a third always-available weapon slot, reusing `Projectile.gd`'s existing arc + splash unmodified) shipped alongside these, per the original plan.

Key architectural choice: `Unit` gained two extra sibling `WeaponHandler` nodes (`SecondaryWeaponHandler`, `GrenadeHandler`) rather than making `WeaponHandler` itself slot-aware — mirrors the precedent `Vehicle.tscn` already set with its driver gun + turret gun as two independent `WeaponHandler` instances on one body. `Unit.gd` just decides which sibling is "active"; `WeaponHandler.gd` itself only needed one small change (`equip(null, ...)` is now a valid "unequip," needed for classes without a secondary/throwable).

AI does not use weapon switching, the repair tool, or grenades this pass (player-only, same phased approach as starfighter flight) — Officer's aura and Sniper's stat differences work for AI bots automatically since neither needs a *decision*, just data.

Lessons worth remembering if this code gets touched again:
- `ConquestMode.gd` calls `Unit.apply_class()` on *every* respawn, not just first spawn (AI bots re-roll a random class each life) — any new per-class runtime setup has to live in `apply_class()` so it resets correctly on a class change mid-match, not just at first spawn. This is why `OfficerAura` gets explicitly `queue_free()`'d and re-instantiated there rather than created once in `_ready()`.
- A raycast fired in the *same frame* a target's `CollisionShape3D` was added to the tree can miss it — Godot's physics server registers new colliders into its broadphase at the next physics step, not synchronously on `add_child()`. Bit a standalone verification harness building test units and firing at them all within one `_ready()` call; fixed by deferring the fire to a later `_process()` tick.
- `HUD.bind_to_unit()` runs *before* `Unit.apply_class()` actually equips anything (`ConquestMode._on_player_class_chosen`'s ordering) — a HUD element whose visibility depends on "is a weapon actually equipped" can't decide that at bind time; it has to be decided from the `ammo_changed` signal instead (which only ever fires for an actually-equipped handler), same class of bug as the pre-existing crosshair-after-death fix.

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

**In-map atmospheric flight is done, player- and AI-usable**, built directly into `Vehicle.gd`/`VehicleData.gd` as a third `MovementType` (`GROUND`/`HOVER`/`FLIGHT`) rather than a separate controller class — the existing `Vehicle`/`VehicleSeat`/`AIBrain` architecture absorbed it cleanly. The starfighter (`scenes/vehicles/starfighter/`) rebuilds its hull's basis fresh each frame from persistent yaw/pitch scalars (matching `CameraRig`'s own pattern), has a BFII-style liftoff/landing sequence (grounded ships are fully input-locked — no pitch/yaw/throttle response at all — until `begin_flight_liftoff()`/`begin_flight_landing()` explicitly transitions them), and AI bots fly it for pure air-to-air dogfights (ground-strafing deliberately out of scope, a bigger follow-up). Lessons worth remembering if this code gets touched again:
- The driver-heading crosshair built for ground/hover vehicles (projects the vehicle's forward onto screen, because those let the mouse look independently of steering) is *wrong* for flight, where the mouse drives the hull directly and aim is always dead-center — `HUD.gd` now branches on `movement_type` to pick the right crosshair behavior.
- A vehicle sitting at rest still runs full physics every frame; nothing stopped it from responding to attitude/throttle input just because it happened to be parked. Fixed by an explicit `_grounded` lock state (`Vehicle._process_parked`) that only lifts through `begin_flight_liftoff()` — this is *why* liftoff/landing exist at all, not just cosmetic sequences.
- AI pitch/yaw steering decomposes the aim problem to match `Vehicle`'s own yaw-then-pitch basis composition (`Basis(UP,yaw)*Basis(RIGHT,pitch)`) exactly, using `Vehicle.get_flight_yaw()`/`get_flight_pitch()` rather than re-deriving heading from the (possibly steeply pitched) 3D forward vector, which degenerates near vertical.
- `Vehicle.gd` clamps the flight ceiling and softly contains the XZ boundary for everyone already, but has no altitude *floor* — fine for a human who can see terrain coming, not fine for AI pursuit. `AIBrain._steer_flight_toward` self-imposes one.
- The chance a bot goes to fly is a per-`ClassData` field (`flight_seek_chance`), not a hardcoded constant, specifically so a future dedicated pilot class can set it much higher without touching `AIBrain.gd`.

**Still to build:**
- A `SpaceZone` scene: same `ConquestMode`-style root, but flight-only (no ground, no gravity), positioned at a large Y offset from the ground map so both can be loaded simultaneously without coordinate precision issues.
- Space `CommandPost`s (subsystem objectives — shields, engines, hangar) register into the same shared `MatchState.command_posts` list ground posts use. No changes needed to `MatchState` itself.
- Capital ship interiors: a hangar `NavigationRegion3D` sized like the ground map's, entered by flying a fighter into a landing-bay trigger volume.
- **Troop transport/dropship** as a natural vehicle type here: the original BF2's AI transports landed at a friendly command post, picked up soldiers, then flew to and landed at an enemy post to deploy them — effectively a live preview of the flight-corridor mechanism below. Reuses the same `Vehicle`/`VehicleSeat` architecture (multiple passenger seats, no weapon needed) plus whatever a zero-gravity `SpaceFlightController` this phase adds needs on top of the atmospheric one.
- AI ground-attack (strafing runs on troops/vehicles) if wanted later — deliberately deferred from the air-to-air pass above.

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
