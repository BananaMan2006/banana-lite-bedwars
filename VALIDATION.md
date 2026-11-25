# Validation record

## November 24, 2026

- Inspected the user's actual Opiumware loader: `https://api.catvape.dev/script`.
- Inspected locally cached CatVape source. Its BedWars module contains 42,380 lines. File size alone is not a performance measurement.
- Read-only live preflight confirmed the Knit, sprint, sword, projectile, queue, shop, block-break and hammer interfaces were exposed.
- First bundle compiled and executed its entire 30-test logic suite in Roblox through Opiumware: **30/30 passed**. Tests cover affordability, absent tools, maxed tiers, stocking limits, Adetunde priorities, ballistic feasibility, purchase serialization/timeouts/replies, and scheduler behavior.
- The panel loaded in the BedWars lobby with all controls OFF. Eleven of twelve dependencies loaded. The `BlockPlacer` module reported a load error in that session; scaffold was correctly unavailable.

## Not established by the above checks

No claim is made yet that a complete 16v16 match, bow damage, melee damage, actual purchase, hammer upgrade, enemy-bed break, bridge placement or cross-server requeue succeeded. No isolated before/after frame-time benchmark has been completed. Feature code is present, but these need end-to-end game validation.

## CatVape audit findings

These are static findings, not a claim that every one caused the user's symptoms:

- Startup in the installed BedWars file waits indefinitely for an internal Knit upvalue; an incompatible game update can leave initialization stuck.
- The remote wrapper caches failed lookups and can return an inert promise-like result instead of surfacing an error.
- AutoBuy catches purchase callback errors without displaying them; it can then set its next wake time to infinity until a subscribed inventory/shop event occurs.
- `BuyTool` treats an absent current tool as an infinite starting index, so that path cannot buy a missing initial tool.
- AutoBuy's prerequisite-upgrade lookup differs from its later per-team upgrade lookup, a compatibility risk requiring live state verification.
- KeepSprint patches a game function constant; it is not simply ordinary auto-sprint. NoFall disables humanoid callbacks and changes velocity. Neither mechanism meets this project's constraint.
- The requested hammer upgrades are implemented by `AutoAdetunde`, separate from generic `AutoKit`.

## Manual acceptance checklist

1. Join 16v16, load with CatVape inactive, and check dependencies.
2. Toggle each control twice; confirm no duplicate UI/jobs, then unload and confirm cleanup.
3. Buy one real item with enough currency and verify inventory/currency changes; test no currency, shop out of range, rejection and delayed responses.
4. Equip Adetunde, earn crystals normally, observe exactly one paid tier increase at a time.
5. For melee/bow: compare actual opponent health, ammo consumption, ordinary range, walls, team filtering, cooldown and death/respawn behavior.
6. Place blocks with decreasing inventory and mine visible enemy-bed cover at the normal tool cooldown.
7. Finish both a winning and losing match and confirm the same queue and restored controls after teleport.
8. Profile frame time with the same player count and controls enabled; do not infer performance solely from source size.
