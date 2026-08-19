# Battleclone

A locally-run, Battlefront II (2005)–style class-based conquest shooter, built in Godot 4, aimed eventually at the seamless ground-to-space combat that was planned (and cut) for Battlefront III. This is an early vertical slice: one ground map, two classes, AI bots, and full conquest capture-point rules. See [ROADMAP.md](ROADMAP.md) for what's next.

## Running it

1. Install [Godot 4.7+](https://godotengine.org/download) (the standard/non-.NET build — this project is pure GDScript, no C# build step). On macOS: `brew install --cask godot`.
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **Play** (or F5). It boots straight into a match — no menu yet.

No package manager, no build step, no external assets to download. Clone and press Play.

## Controls

| Action | Key |
|---|---|
| Move | WASD |
| Sprint | Shift (while moving forward) |
| Crouch | C |
| Jump | Space |
| Look | Mouse |
| Fire | Left Mouse |
| Aim (zoom) | Right Mouse |
| Reload | R |
| Toggle first/third person | V |
| Pause / free cursor | Esc |

## What's here

- **Conquest mode**: capture command posts, bleed the enemy's reinforcement tickets, win by ticket-out or capturing every post.
- **Two classes** (Trooper, Heavy) proving a data-driven class/weapon system — new classes/weapons are authored as `.tres` resources under `resources/`, not code.
- **AI bots** that run through the exact same movement/combat code as the player (they're driven by `AIBrain.gd` instead of `PlayerInput.gd`), so they fight fairly and by the same rules.
- **Grey-box art**: primitives and flat colors everywhere. All effort so far went into making the mechanics solid; visuals come later.

## Project layout

```
scenes/     .tscn scene files (units, weapons, maps, UI, gamemode)
scripts/    .gd source, mirrors scenes/ by system
resources/  data-driven .tres instances (weapons, classes, factions)
```

See the **Architecture** section of [ROADMAP.md](ROADMAP.md) for how the pieces fit together, especially the shared player/AI "Unit" architecture and how it's meant to extend to vehicles and space combat.
