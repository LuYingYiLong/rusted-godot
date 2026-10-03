# 原版单位目录

由 `tools/generate_rw_vanilla_unit_catalog.py` 从 RWX 的 `UnitTypeEnum.java` 与 `assets/units/**/*.ini` 生成。`RwVanillaUnitCatalog` 是打包时可用的静态目录；源 INI 路径仅供核对，不表示文件已复制进 Godot 项目

- 原生枚举类型：52 个，索引从 0 开始；包含环境与编辑器辅助对象
- 可载入的内置自定义单位：121 个，网络类型为 `-2` 加单位名；已与 `RwVanillaUnits.HASHES` 全量核对
- 覆盖原生类型的内置自定义单位：18 个；`overrideAndReplace: NONE` 不算覆盖
- Godot 已注册 52 个原生类型和 121 个内置自定义单位的基础定义；已配置的建筑建造别名：6 个。基础定义不代表战斗与生产行为已完成

内置单位的主体、炮塔、静态腿部、阴影与帧动画由 `RwBuiltinUnitSpecs` 提供；相关 PNG 已复制到 `assets/rwx/units` 并通过 UID 目录载入。复杂单位的腿部步态、逐炮塔瞄准、形态切换和特殊技能仍需后续行为与网络状态支持

`变体归属` 根据 INI 中的 `convertTo` 和临时转换关系分组。空白表示关系图中的基础项或独立项；它不保证该项能被玩家生产。`生产来源` 合并同目录 `copyFrom` 后读取 `builtFrom_*_name`；转换目标只读取本文件声明的动作，未展开动作段继承或动态脚本动作。`[comment_*]` 配置段不计入有效动作

## 原生类型

| 网络索引 | 原生名称 | 内置替换名 | Godot 定义 |
| ---: | --- | --- | --- |
| 0 | `extractor` | extractorT1 | 已注册 |
| 1 | `landFactory` | — | 已注册 |
| 2 | `airFactory` | — | 已注册 |
| 3 | `seaFactory` | — | 已注册 |
| 4 | `commandCenter` | — | 已注册 |
| 5 | `turret` | c_turret_t1 | 已注册 |
| 6 | `antiAirTurret` | c_antiAirTurret | 已注册 |
| 7 | `builder` | — | 已注册 |
| 8 | `tank` | c_tank | 已注册 |
| 9 | `hoverTank` | — | 已注册 |
| 10 | `artillery` | c_artillery | 已注册 |
| 11 | `helicopter` | c_helicopter | 已注册 |
| 12 | `airShip` | c_interceptor | 已注册 |
| 13 | `gunShip` | — | 已注册 |
| 14 | `missileShip` | — | 已注册 |
| 15 | `gunBoat` | — | 已注册 |
| 16 | `megaTank` | — | 已注册 |
| 17 | `laserTank` | c_laserTank | 已注册 |
| 18 | `hovercraft` | — | 已注册 |
| 19 | `ladybug` | — | 已注册 |
| 20 | `battleShip` | — | 已注册 |
| 21 | `tankDestroyer` | — | 已注册 |
| 22 | `heavyTank` | — | 已注册 |
| 23 | `heavyHoverTank` | — | 已注册 |
| 24 | `laserDefence` | — | 已注册 |
| 25 | `dropship` | — | 已注册 |
| 26 | `tree` | — | 已注册 |
| 27 | `repairbay` | — | 已注册 |
| 28 | `NukeLaucher` | nukeLauncherC | 已注册 |
| 29 | `AntiNukeLaucher` | antiNukeLauncherC | 已注册 |
| 30 | `mammothTank` | c_mammothTank | 已注册 |
| 31 | `experimentalTank` | c_experimentalTank | 已注册 |
| 32 | `experimentalLandFactory` | — | 已注册 |
| 33 | `crystalResource` | — | 已注册 |
| 34 | `wall_v` | — | 已注册 |
| 35 | `fabricator` | fabricatorT1 | 已注册 |
| 36 | `attackSubmarine` | — | 已注册 |
| 37 | `builderShip` | — | 已注册 |
| 38 | `amphibiousJet` | — | 已注册 |
| 39 | `supplyDepot` | — | 已注册 |
| 40 | `experimentalHoverTank` | — | 已注册 |
| 41 | `turret_artillery` | c_turret_t1_artillery | 已注册 |
| 42 | `turret_flamethrower` | c_turret_t2_flame | 已注册 |
| 43 | `fogRevealer` | — | 已注册 |
| 44 | `spreadingFire` | — | 已注册 |
| 45 | `antiAirTurretT2` | c_antiAirTurretT2 | 已注册 |
| 46 | `turretT2` | c_turret_t2_gun | 已注册 |
| 47 | `turretT3` | c_turret_t3_gun | 已注册 |
| 48 | `damagingBorder` | — | 已注册 |
| 49 | `zoneMarker` | — | 已注册 |
| 50 | `editorOrBuilder` | — | 已注册 |
| 51 | `dummyNonUnitWithTeam` | — | 已注册 |

## 内置自定义单位

| 名称 | 变体归属 | 覆盖原生类型 | 科技等级 | 生产来源 | 转换目标 | 临时形态 | Godot 状态 | RWX INI |
| --- | --- | --- | ---: | --- | --- | --- | --- | --- |
| `aaBeamGunship` | — | — | 2 | airFactory | aaBeamGunship_afterburn | — | 已注册基础定义 | `assets/units/aa_beam_gunship/aa_beam_gunship.ini` |
| `aaBeamGunship_afterburn` | aaBeamGunship | — | 2 | — | aaBeamGunship | — | 已注册基础定义 | `assets/units/aa_beam_gunship/aa_beam_gunship_afterburn.ini` |
| `antiAirTurretFlak` | c_antiAirTurret | — | 1 | — | — | — | 已注册基础定义 | `assets/units/turrets/turret_antiair_flakgun.ini` |
| `antiNukeLauncherC` | — | AntiNukeLaucher | 1 | — | — | — | 已注册；建筑建造别名 | `assets/units/nukes/antinuke_launcher.ini` |
| `bomber` | — | — | 2 | airFactory | — | — | 已注册基础定义 | `assets/units/bomber/bomber.ini` |
| `bugBee` | — | — | 1 | bugNest | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_bee/bug_bee.ini` |
| `bugExtractor` | — | — | 1 | — | bugExtractorT2 | — | 已注册基础定义 | `assets/units/classic_bugs/bug_extractor/bug_extractor.ini` |
| `bugExtractorT2` | bugExtractor | — | 2 | — | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_extractor/bug_extractorT2.ini` |
| `bugFly` | — | — | 1 | bugNest | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_fly/bug_fly.ini` |
| `bugGenerator` | — | — | 1 | — | bugGeneratorT2 | — | 已注册基础定义 | `assets/units/classic_bugs/bug_generator/bug_generator.ini` |
| `bugGeneratorN` | — | — | 1 | — | bugGeneratorNT2 | — | 已注册基础定义 | `assets/units/bug_base/bug_generator/bug_generator.ini` |
| `bugGeneratorNT2` | bugGeneratorN | — | 2 | — | — | — | 已注册基础定义 | `assets/units/bug_base/bug_generator/bug_generatorT2.ini` |
| `bugGeneratorT2` | bugGenerator | — | 2 | — | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_generator/bug_generatorT2.ini` |
| `bugMelee` | — | — | 1 | bugNest | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_melee/bug_melee.ini` |
| `bugMeleeLarge` | — | — | 1 | — | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_melee/bug_melee_large.ini` |
| `bugMeleeSmall` | — | — | 1 | — | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_melee/bug_melee_small.ini` |
| `bugMeleeT31` | — | — | 1 | — | — | — | 已注册基础定义 | `assets/units/bug_melee/bug_melee_t31.ini` |
| `bugNest` | — | — | 1 | — | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_nest/bug_nest.ini` |
| `bugPickup` | — | — | 1 | bugNest | — | — | 已注册基础定义 | `assets/units/classic_bugs/bugs/bug_pickup.ini` |
| `bugRanged` | — | — | 1 | bugNest | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_ranged/bug_ranged.ini` |
| `bugRangedT2` | — | — | 1 | bugNest | — | — | 已注册基础定义 | `assets/units/classic_bugs/bugs_t2/bug_ranged_t2.ini` |
| `bugSpore` | — | — | 1 | bugNest | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_spore/bug_spore.ini` |
| `bugTurret` | — | — | 1 | — | — | — | 已注册基础定义 | `assets/units/classic_bugs/bug_turret/bug_turret.ini` |
| `bugWasp` | — | — | 1 | bugNest | — | — | 已注册基础定义 | `assets/units/classic_bugs/bugs/bug_wasp.ini` |
| `c_amphibiousJet` | — | — | 2 | — | c_amphibiousJet_underwater | c_amphibiousJet_transition | 已注册基础定义 | `assets/units/amphibious_jet/amphibious_jet.ini` |
| `c_amphibiousJet_transition` | c_amphibiousJet | — | 2 | — | — | — | 已注册基础定义 | `assets/units/amphibious_jet/amphibious_jet_transition.ini` |
| `c_amphibiousJet_underwater` | c_amphibiousJet | — | 2 | — | c_amphibiousJet | c_amphibiousJet_transition | 已注册基础定义 | `assets/units/amphibious_jet/amphibious_jet_underwater.ini` |
| `c_antiAirTurret` | — | antiAirTurret | 1 | — | c_antiAirTurretT2, antiAirTurretFlak | — | 已注册；建筑建造别名 | `assets/units/turrets/turret_antiair.ini` |
| `c_antiAirTurretT2` | c_antiAirTurret | antiAirTurretT2 | 1 | — | c_antiAirTurretT3 | — | 已注册基础定义 | `assets/units/turrets/turret_antiair_t2.ini` |
| `c_antiAirTurretT3` | c_antiAirTurret | — | 1 | — | — | — | 已注册基础定义 | `assets/units/turrets/turret_antiair_t3.ini` |
| `c_artillery` | — | artillery | 1 | — | — | — | 已注册基础定义 | `assets/units/tanks/artillery.ini` |
| `c_experimentalTank` | — | experimentalTank | 2 | — | — | — | 已注册基础定义 | `assets/units/experimental_tank/experimental_tank.ini` |
| `c_helicopter` | — | helicopter | 1 | airFactory | — | — | 已注册基础定义 | `assets/units/helicopter/helicopter.ini` |
| `c_interceptor` | — | airShip | 1 | airFactory | — | — | 已注册基础定义 | `assets/units/interceptor/interceptor.ini` |
| `c_laserTank` | — | laserTank | 2 | — | — | — | 已注册基础定义 | `assets/units/laser_tank/laser_tank.ini` |
| `c_mammothTank` | — | mammothTank | 2 | landFactory | — | — | 已注册基础定义 | `assets/units/mammoth_tank/mammoth_tank.ini` |
| `c_tank` | — | tank | 1 | — | — | — | 已注册基础定义 | `assets/units/tanks/tank.ini` |
| `c_turret_t1` | — | turret | 1 | — | c_turret_t2_gun, c_turret_t1_artillery, c_turret_t2_flame, c_turret_t1_lightning | — | 已注册；建筑建造别名 | `assets/units/turrets/turret_t1.ini` |
| `c_turret_t1_artillery` | c_turret_t1 | turret_artillery | 2 | — | c_turret_t2_artillery | — | 已注册基础定义 | `assets/units/turrets/turret_t1_artillery.ini` |
| `c_turret_t1_lightning` | c_turret_t1 | — | 2 | — | c_turret_t2_lightning | — | 已注册基础定义 | `assets/units/turrets/turret_t1_lightning.ini` |
| `c_turret_t2_artillery` | c_turret_t1 | — | 2 | — | — | — | 已注册基础定义 | `assets/units/turrets/turret_t2_artillery.ini` |
| `c_turret_t2_flame` | c_turret_t1 | turret_flamethrower | 2 | — | — | — | 已注册基础定义 | `assets/units/turrets/turret_t2_flame.ini` |
| `c_turret_t2_gun` | c_turret_t1 | turretT2 | 2 | — | c_turret_t3_gun | — | 已注册基础定义 | `assets/units/turrets/turret_t2_gun.ini` |
| `c_turret_t2_lightning` | c_turret_t1 | — | 2 | — | — | — | 已注册基础定义 | `assets/units/turrets/turret_t2_lightning.ini` |
| `c_turret_t3_gun` | c_turret_t1 | turretT3 | 2 | — | — | — | 已注册基础定义 | `assets/units/turrets/turret_t3_gun.ini` |
| `combatEngineer` | — | — | 2 | landFactory, experimentalLandFactory | — | — | 已注册基础定义 | `assets/units/combat_engineer/combat_engineer.ini` |
| `creditsCrates` | — | — | 1 | — | — | — | 已注册基础定义 | `assets/units/resource_deposits/creditsCrate.ini` |
| `crystal_mid` | — | — | 1 | — | — | — | 已注册基础定义 | `assets/units/resource_deposits/crystal_mid.ini` |
| `experiementalCarrier` | — | — | 2 | seaFactory | — | — | 已注册基础定义 | `assets/units/experimental_carrier/Experiemental_carrier.ini` |
| `experimentalDropship` | — | — | 1 | experimentalLandFactory | — | — | 已注册基础定义 | `assets/units/experimental_dropship/experimental_dropship.ini` |
| `experimentalGunship` | — | — | 1 | — | experimentalGunshipLanded | — | 已注册基础定义 | `assets/units/experimental_gunship/experimental_gunship.ini` |
| `experimentalGunshipLanded` | experimentalGunship | — | 1 | — | experimentalGunship | — | 已注册基础定义 | `assets/units/experimental_gunship/experimental_gunship_landed.ini` |
| `experimentalSpider` | — | — | 1 | experimentalLandFactory | — | — | 已注册基础定义 | `assets/units/experimental_spider/experimental_spider.ini` |
| `extractorT1` | — | extractor | 1 | — | extractorT2 | — | 已注册；建筑建造别名 | `assets/units/extractor/extractor.ini` |
| `extractorT2` | extractorT1 | — | 2 | — | extractorT3 | — | 已注册基础定义 | `assets/units/extractor/extractorT2.ini` |
| `extractorT3` | extractorT1 | — | 3 | — | extractorT3_overclocked, extractorT3_reinforced | — | 已注册基础定义 | `assets/units/extractor/extractorT3.ini` |
| `extractorT3_overclocked` | extractorT1 | — | 3 | — | extractorT3 | — | 已注册基础定义 | `assets/units/extractor/extractorT3_overclocked.ini` |
| `extractorT3_reinforced` | extractorT1 | — | 3 | — | extractorT3 | — | 已注册基础定义 | `assets/units/extractor/extractorT3_reinforced.ini` |
| `fabricatorT1` | — | fabricator | 1 | — | fabricatorT2 | — | 已注册；建筑建造别名 | `assets/units/fabricator/fabricatorT1.ini` |
| `fabricatorT2` | fabricatorT1 | — | 2 | — | fabricatorT3 | — | 已注册基础定义 | `assets/units/fabricator/fabricatorT2.ini` |
| `fabricatorT3` | fabricatorT1 | — | 2 | — | — | — | 已注册基础定义 | `assets/units/fabricator/fabricatorT3.ini` |
| `fireBee` | — | — | 1 | experimentalLandFactory | — | — | 已注册基础定义 | `assets/units/fire_bee/fire_bee.ini` |
| `flare_10s` | — | — | — | — | — | — | 已注册基础定义 | `assets/units/miscellaneous/flare_10s.ini` |
| `heavyAAShip` | — | — | 2 | seaFactory | — | — | 已注册基础定义 | `assets/units/heavy_aa_ship/heavy_aa_ship.ini` |
| `heavyArtillery` | — | — | 2 | landFactory | — | — | 已注册基础定义 | `assets/units/tanks/heavy_artillery.ini` |
| `heavyBattleship` | — | — | 2 | seaFactory | — | — | 已注册基础定义 | `assets/units/heavy_battleship/heavy_battleship.ini` |
| `heavyInterceptor` | — | — | 2 | airFactory | — | — | 已注册基础定义 | `assets/units/heavy_interceptor/heavyInterceptor.ini` |
| `heavyMissileShip` | — | — | 2 | seaFactory | — | — | 已注册基础定义 | `assets/units/heavy_missile_ship/heavy_missile_ship.ini` |
| `heavySub` | — | — | 2 | seaFactory | — | — | 已注册基础定义 | `assets/units/heavy_sub/heavy_sub.ini` |
| `laboratory` | — | — | 2 | — | — | — | 已注册基础定义 | `assets/units/laboratory/laboratory.ini` |
| `lightGunship` | — | — | 1 | airFactory | — | — | 已注册基础定义 | `assets/units/light_gunship/light_gunship.ini` |
| `lightSub` | — | — | 1 | seaFactory | — | — | 已注册基础定义 | `assets/units/light_sub/light_sub.ini` |
| `mechArtillery` | — | — | 1 | mechFactory, mechFactoryT2 | — | — | 已注册基础定义 | `assets/units/mechs_large/mech_artillery.ini` |
| `mechBunker` | — | — | 1 | mechFactory, mechFactoryT2 | mechBunkerDeployed | — | 已注册基础定义 | `assets/units/mechs_large/mech_bunker.ini` |
| `mechBunkerDeployed` | mechBunker | — | 1 | — | mechBunker | — | 已注册基础定义 | `assets/units/mechs_large/mech_bunker_deployed.ini` |
| `mechEngineer` | — | — | 2 | mechFactoryT2 | — | — | 已注册基础定义 | `assets/units/mech_engineer/mech_engineer.ini` |
| `mechFactory` | — | — | 1 | builder, experimentalSpider | mechFactoryT2 | — | 已注册基础定义 | `assets/units/mech_factory/mechFactory.ini` |
| `mechFactoryT2` | mechFactory | — | 2 | experimentalSpider | — | — | 已注册基础定义 | `assets/units/mech_factory/mechFactoryT2.ini` |
| `mechFlame` | — | — | 2 | mechFactoryT2 | — | — | 已注册基础定义 | `assets/units/mechs_large/mech_flame.ini` |
| `mechFlyingLanded` | — | — | 2 | — | mechFlyingTakeoff | — | 已注册基础定义 | `assets/units/mechs_large/mech_flying_landed.ini` |
| `mechFlyingTakeoff` | mechFlyingLanded | — | 2 | — | mechFlyingLanded | — | 已注册基础定义 | `assets/units/mechs_large/mech_flying_takeoff.ini` |
| `mechGun` | — | — | 1 | mechFactory, mechFactoryT2 | — | — | 已注册基础定义 | `assets/units/mechs_small/mech_gun.ini` |
| `mechHeavyMissile` | — | — | 2 | mechFactoryT2 | — | — | 已注册基础定义 | `assets/units/mechs_large/mech_heavyMissile.ini` |
| `mechLaser` | — | — | 2 | mechFactoryT2 | — | — | 已注册基础定义 | `assets/units/mechs_large/mech_laser.ini` |
| `mechLightning` | — | — | 2 | mechFactoryT2 | — | — | 已注册基础定义 | `assets/units/mechs_large/mech_lightning.ini` |
| `mechMinigun` | — | — | 2 | mechFactoryT2 | — | — | 已注册基础定义 | `assets/units/mechs_large/mech_minigun.ini` |
| `mechMissile` | — | — | 1 | mechFactory, mechFactoryT2 | — | — | 已注册基础定义 | `assets/units/mechs_small/mech_missile.ini` |
| `missileAirship` | — | — | 2 | airFactory | — | — | 已注册基础定义 | `assets/units/missile_airship/missile_airship.ini` |
| `missileTank` | — | — | 2 | landFactory | — | — | 已注册基础定义 | `assets/units/missile_tank/missile_tank.ini` |
| `missing` | — | — | 1 | — | — | — | 已注册基础定义 | `assets/units/missing_unit/missing.ini` |
| `modularSpider` | — | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/modular_spider.ini` |
| `modularSpider_antiair` | modularSpider_emptySlot | — | 1 | — | modularSpider_antiairT2, modularSpider_antiairFlak | — | 已注册基础定义 | `assets/units/modular_spider/antiair.ini` |
| `modularSpider_antiairFlak` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/antiairFlak.ini` |
| `modularSpider_antiairT2` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/antiairT2.ini` |
| `modularSpider_antinuke` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/antinuke.ini` |
| `modularSpider_artillery` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/artillery.ini` |
| `modularSpider_blink` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/blink.ini` |
| `modularSpider_emptySlot` | — | — | 1 | — | modularSpider_smallgunturret, modularSpider_gunturret, modularSpider_lightning, modularSpider_artillery, modularSpider_antiair, modularSpider_fabricator, modularSpider_laserdefense, modularSpider_shieldGen, modularSpider_speedIncomplete, modularSpider_antinuke, modularSpider_blink | — | 已注册基础定义 | `assets/units/modular_spider/emptySlot.ini` |
| `modularSpider_fabricator` | modularSpider_emptySlot | — | 1 | — | modularSpider_fabricatorT2 | — | 已注册基础定义 | `assets/units/modular_spider/fabricator.ini` |
| `modularSpider_fabricatorT2` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/fabricatorT2.ini` |
| `modularSpider_gunturret` | modularSpider_emptySlot | — | 1 | — | modularSpider_gunturretT2 | — | 已注册基础定义 | `assets/units/modular_spider/gunturret.ini` |
| `modularSpider_gunturretT2` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/gunturretT2.ini` |
| `modularSpider_laserdefense` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/laser_defense.ini` |
| `modularSpider_lightning` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/lightning.ini` |
| `modularSpider_nonEmpty` | modularSpider | — | 1 | — | modularSpider | — | 已注册基础定义 | `assets/units/modular_spider/modular_spider_nonEmpty.ini` |
| `modularSpider_shieldGen` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/shieldGen.ini` |
| `modularSpider_smallgunturret` | modularSpider_emptySlot | — | 1 | — | modularSpider_smallgunturretT2 | — | 已注册基础定义 | `assets/units/modular_spider/smallgun.ini` |
| `modularSpider_smallgunturretT2` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/smallgunT2.ini` |
| `modularSpider_speed` | modularSpider_emptySlot | — | 1 | — | — | — | 已注册基础定义 | `assets/units/modular_spider/speed.ini` |
| `modularSpider_speedIncomplete` | modularSpider_emptySlot | — | 1 | — | modularSpider_speed | — | 已注册基础定义 | `assets/units/modular_spider/speed_incomplete.ini` |
| `nautilusSubmarine` | — | — | 2 | seaFactory | nautilusSubmarineLand, nautilusSubmarineSurface, nautilusSubmarine | — | 已注册基础定义 | `assets/units/nautilus/nautilus.ini` |
| `nautilusSubmarineLand` | nautilusSubmarine | — | 2 | experimentalLandFactory | nautilusSubmarineSurface | — | 已注册基础定义 | `assets/units/nautilus/nautilusLand.ini` |
| `nautilusSubmarineSurface` | nautilusSubmarine | — | 2 | — | — | — | 已注册基础定义 | `assets/units/nautilus/nautilusSurface.ini` |
| `nukeLauncherC` | — | NukeLaucher | 1 | — | — | — | 已注册；建筑建造别名 | `assets/units/nukes/nuke_launcher.ini` |
| `outpostT1` | — | — | 1 | — | outpostT2 | — | 已注册基础定义 | `assets/units/outpost/outpost.ini` |
| `outpostT2` | outpostT1 | — | 2 | — | — | — | 已注册基础定义 | `assets/units/outpost/outpostT2.ini` |
| `plasmaTank` | — | — | 2 | landFactory | — | — | 已注册基础定义 | `assets/units/plasma_tank/plasma_tank.ini` |
| `robotCrab` | — | — | 1 | — | robotCrabWater | — | 已注册基础定义 | `assets/units/nautilus/robotCrab/robotCrab.ini` |
| `robotCrabWater` | robotCrab | — | 1 | — | robotCrab | — | 已注册基础定义 | `assets/units/nautilus/robotCrab/robotCrabWater.ini` |
| `scout` | — | — | 1 | commandCenter, landFactory | — | — | 已注册基础定义 | `assets/units/scout/scout.ini` |
| `spyDrone` | — | — | 2 | airFactory | — | — | 已注册基础定义 | `assets/units/spy_drone/spy_drone.ini` |

## 源数据中待核对的关系

所有直接引用都能在本目录中解析

## 重新生成

```powershell
python tools/generate_rw_vanilla_unit_catalog.py 'C:\Users\Administrator\Downloads\RWX-main\RWX-main'
```

运行时仅使用生成的 GDScript 常量，不会扫描 RWX 目录。第三方 Mod 不属于本目录
