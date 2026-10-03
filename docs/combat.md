# Combat system

`RwBattleCombat` runs after movement and production once per synchronized battle frame. It visits units in object ID order, invokes each unit's behavior, advances projectiles, and applies damage. The battle map owns the combat system and handles deaths, building obstacles, income sources, selection, and the minimap.

## Define a unit

- `RwUnitDefinition.weapon_parts` describes drawn sprites and their rotation state indexes
- `RwUnitDefinition.combat_weapons` describes targeting, cooldown, muzzle position, and projectiles
- `RwUnitDefinition.behavior` is an optional, stateless `RwUnitBehavior` resource
- `RwAutoAttackBehavior` uses the shared targeting and firing implementation

Behavior resources may be shared by many units. Store per-unit mutable state on `RwUnitState` or in a battle system keyed by object ID. Behavior callbacks receive a `RwCombatContext` rather than a scene node. Keep frame callbacks deterministic: do not read wall time, local camera state, or unseeded randomness to decide gameplay outcomes.

`RwProjectileDefinition` supports direct and splash damage, homing, a lifetime, an optional texture region, and a colored circle fallback. `RwBattleProjectileLayer` only draws projectiles; it never changes battle state. `RwBattleCombat` emits `projectile_fired`, `projectile_impacted`, and `unit_destroyed` for sound and visual effects.

## Current vanilla coverage

Tank and tier-one gun turret use the new system. Their damage, range, reload time, and projectile speed follow the corresponding RWX implementations. Their target selection, aim, collision, and projectile visuals are a first pass and have not yet been proven frame-identical to the vanilla engine. Other vanilla units still need weapon and behavior definitions before they can fight. Do not treat this first pass as verified lockstep combat compatibility with vanilla rooms.

Run the focused check with:

```powershell
& 'C:\Users\Administrator\Documents\Godot\Godot_v4.7.2-stable_win64.exe' --headless --path . --script tests/rw_battle_combat_test.gd
```
