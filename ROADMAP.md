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

## Phase 2 — Vehicles (done: speeder bike + walker)

Built: `Vehicle.gd`/`VehicleSeat.gd`/`VehicleData.gd`/`VehicleHealth.gd` (`scripts/vehicle/`), reusing `Health`/`WeaponHandler` exactly as `Unit.gd` does. Seats possess the occupant's `PlayerInput` the same way `PlayerInput`/`AIBrain` drive `Unit` — enter/exit mirrors `Unit`'s own hide/disable pattern, so the soldier is paused not destroyed. Two vehicles live at `scenes/vehicles/`: the speeder bike (single seat, fast/fragile hover) and the AT-ST-style walker (driver + independently-aimed gunner turret, slow/armored, grounded). Vehicles carry a regenerating shield in front of health, and AI bots can target/fire on them (confirmed working live). Playtesting caught and fixed two real bugs worth remembering: vehicle `CameraRig`s auto-activating on spawn (fixed via `start_active`/`activate()`), and the walker's two seat triggers fully overlapping so the gunner seat was unreachable (fixed by spatially separating them).

**Remaining vehicle work, not yet built:**
- AI *driving* vehicles — deferred by design this pass. Can reuse `AIBrain`'s state machine shape (advance/engage/capture) with `NavigationAgent3D` swapped for simpler point-to-point steering.
- Direct seat-to-seat swap (driver ↔ gunner) without exiting first — currently `interact` while possessed always exits; confirmed acceptable UX for now, but a small addition to `VehicleSeat`/`PlayerInput` if wanted later.
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
