# BananaLite — BedWars 16v16

An original, small experimental client helper. It does not load CatVape, patch game functions, expand hitboxes, suppress fall damage, or change physics. The game's normal movement, combat, placement, mining, purchase and cooldown rules remain in place.

**Status: prototype, not a verified replacement for all CatVape features.** The initial 30 decision-logic tests passed in Roblox Luau on November 24, 2026. The expanded 40-test suite passed locally in Lua 5.5.1; the final bundle also passed syntax compilation. In 16v16, all 12 dependencies loaded and bed/opponent labels rendered. Purchases, damage and cross-server reload are not confirmed. See `VALIDATION.md` for the exact limits of these checks.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/BananaMan2006/banana-lite-bedwars/main/banana-lite.lua"))()
```

Load after joining a BedWars match. Unload CatVape and rejoin first if it was active: its hooks alter the game interfaces, so running both would invalidate testing. Every feature starts OFF. RightShift shows/hides the panel; **Unload** stops the helper and removes its UI. No account credentials or external telemetry are used.

## Controls

| Control | Actual behavior |
|---|---|
| KeepSprint | Requests ordinary sprint while moving. Does not remove slowing effects or raise speed. |
| Melee assist | Uses the native swing selection for the nearest visible, on-screen opponent inside the held weapon's normal range. Requires an equipped ordinary sword; special charged weapons are skipped. The box marks a candidate, not confirmed damage. |
| Bow assist | Requires an equipped bow/crossbow and ammo. Waits the configured charge time, computes a physical arc, checks for obstructions, and uses the ordinary projectile launch interface. No through-wall shots or guaranteed hits. |
| BedESP | Simple labels on replicated beds. No animated effects. |
| Nametags | Labels living opponents; updates twice per second and cleans up on respawn/removal. |
| AutoQueue | Requests the current mode after match end when you are party leader. Attempts to reload this script and restore controls through the executor's teleport queue. Automatic restoration failed in the first test; revised handling is still unverified. It does not abandon a living team on your death. |
| Chat phrases | Enter one phrase per line. Random selection at most every 15 seconds; empty input sends nothing. Uses ordinary filtered Roblox chat. |
| Scaffold | Prefers wool, otherwise an inventory block; places one cell ahead through the native placer. No tower, teleport, placement-range changes or inventory fabrication. |
| Bed breaker | Mines the visible block toward a nearby enemy bed, using the equipped tool and native reach/cooldown. Does not remove bed shields, skip covering blocks or guarantee an optimal route. |
| AutoBuy | Within 16 studs of an item shop: a wool floor, armor, ordinary sword (skipped with Adetunde), tools, bow/arrows, then more wool. Uses the live item catalog and sends one purchase at a time. Team diamond upgrades are not implemented. |
| AutoKit | Adetunde only. Chooses affordable hammer upgrades, lower tiers first and strength before speed/shield at equal tier. Waits for the replicated tier to change. |

Fly and NoFall are deliberately absent because the requested behavior would override ordinary 16v16 movement/damage rules. Map-wide melee, hitbox inflation, guaranteed projectile hits and wall penetration are likewise outside this build's scope.

## Reliability

- One scheduler, bounded update frequencies, no catch-up bursts, and no overlapping runs of the same feature.
- Dependency loading has a deadline and bounded retries. Missing dependencies disable only affected controls.
- Failed actions display an error; repeated failures disable that control.
- Purchase acknowledgement and inventory confirmation are distinct. An ambiguous timeout pauses the buyer rather than sending duplicate purchases. Resolve the inventory/server response before restarting; repeated execution is not a repair for a rejected purchase.
- The internal BedWars interfaces are not a stable public scripting API. Game updates can require adapter changes.
- Public-match automation being accepted by a server is not a statement of endorsement or permission from the game developer.

## Development

`core.lua` contains deterministic decisions. `selftest.lua` tests edge cases. `runtime.lua` contains the Roblox adapter and panel. `python3 build.py` produces the single-file `banana-lite.lua` bundle without fetching dependencies.

With a local Lua 5.3+ interpreter, run `lua -e 'math.atan2=math.atan; dofile("selftest.lua")(dofile("core.lua"))'` from this directory. This exercises decisions only, not Roblox adapters. `shared.BananaLite:Diagnostics()` reports dependency availability, feature errors and observed purchase/upgrade counts during a live session.

Run the bundled tests without loading the UI:

```lua
shared.BananaLiteSelfTest = true
loadstring(game:HttpGet("https://raw.githubusercontent.com/BananaMan2006/banana-lite-bedwars/main/banana-lite.lua"))()
```

The source is original; the installed CatVape files were inspected for compatibility and are not redistributed here.
