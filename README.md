# Delirium Heating

Build 42 mod for the Delirium server. No dependencies.

District heating for a world without grid power: one boiler house heats a whole neighbourhood.

- **Boiler house** (2x3 cells): burns fuel and heats the water. Anyone lights it or puts it out and loads fuel from the context menu: logs, firewood, planks, branches, charcoal, coke, a propane tank (drained, the empty tank stays) or petrol (poured out of its container). The water warms up by a degree a game minute and cools down slowly when the fire is out.
- **Pipes** lie on the ground and do not block the way. They join their neighbours by themselves, also the cell above or below (a riser).
- **Pump stations**: the water travels 40 cells of pipe from the boiler house; a pump station on the way sends it 80 cells further. A pump needs electricity (a generator in range); without it it is just a pipe.
- **Radiators** stand in the rooms, on a pipe. A radiator the hot water reaches warms the air around it the way a vanilla fireplace does (an `IsoHeatSource`): walls and closed doors stop the heat. They start to warm at 30 degrees of water and give full heat at 80.
- Fuel: an idle boiler burns 1 unit a game hour, plus 0.05 for every radiator it feeds; a log is 6 units, the furnace holds 500.

Everything is placed by an **admin** from the context menu, **Heating (admin)**:

- *Pipe here*, or a run: *Pipe run: start here* on one cell, then *Pipe run: lay to here* on another (along x, then along y; up to 200 cells; cells already taken are passed over). The next run starts where the last one ended. *Remove pipes to here* takes a run off.
- *Radiator here* (at the north, west, south or east wall of the cell), *Pump station here*, *Boiler house* (front to the south or to the east; the clicked cell is the middle of the front).
- On a placed object: *Check the supply* (does the water get here and how much further it would go), *Fill with fuel*, *Remove*.

The objects cannot be picked up or broken with a sledgehammer.

## Sandbox options (page DelHeat)

| Option | Default | Meaning |
|---|---|---|
| `FuelCapacity` | 500 | fuel units a boiler house holds; one unit is one game hour of an idle boiler |
| `BurnPerHour` | 1 | units a lit boiler burns each game hour |
| `BurnPerRadiator` | 0.05 | extra units per hour for every radiator fed |
| `HeatUpPerMinute` | 1 | water heats up, degrees per game minute |
| `CoolDownPerMinute` | 0.25 | water cools down, degrees per game minute |
| `BoilerReach` | 40 | cells of pipe the water travels from a boiler house |
| `PumpReach` | 80 | cells a working pump sends it further |
| `PumpNeedsPower` | true | a pump works only on a powered square |
| `RadiatorTemp` | 35 | air temperature at a radiator at full heat (a fireplace is 35) |
| `RadiatorRadius` | 6 | cells at which the heat fades to nothing |
| `PetrolPerLitre` | 2 | units per litre of petrol, 0 to refuse petrol |
| `FuelTable` | `Base.Log:6; Base.Firewood:2; Base.Plank:2; ...; Base.PropaneTank:80` | item:units pairs |

Tiles: pack `delheat`, `tiledef=delheat 1919`. Art is modelled from primitives and rendered with the PZ camera: `art/render_heat.py` (Blender) -> `art/cut_heat.py` (frames, `art/tiles.json`) -> `tools/TilePack/build-tilepack.ps1`. Translations are written by `art/make_translations.py`.
