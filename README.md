# Delirium Heating

Build 42 mod for the Delirium server. Requires **Delirium Economy** (and through it Delirium Shops).

District heating for a world without grid power: one boiler house heats a whole neighbourhood.

- **Water intake** (2x2 cells, next to a river or a lake): pumps water into the pipes. Every working intake whose water reaches a boiler house adds 200 l a game hour to its tank. Needs electricity.
- **Boiler house** (2x3 cells): burns fuel and heats the water. It does not burn without water in its tank (1000 l; a burning boiler loses 10 l an hour plus 0.5 per radiator). Anyone lights it or puts it out and loads fuel from the context menu: logs, firewood, planks, branches, charcoal, coke, a propane tank (drained, the empty tank stays) or petrol (poured out of its container). The water warms up by a degree a game minute and cools down slowly when the fire is out.
- **Pipes** lie on the ground and do not block the way. They join their neighbours by themselves. One kind of pipe carries both the intake's water to the boiler and the hot water from it.
- **Pipes in the air**, to cross a road: build a floor one level up, lay the pipes on it and take the floor away - the pipes stay. A pipe joins the pipe right above or below it, and the lower one shows a riser, so a run goes up, over and down again. A pipe one level up is taken apart from the ground below it.
- **Pump stations**: the water travels 60 cells of pipe from an intake and 40 from a boiler house; a pump station on the way sends it 80 cells further. A pump needs electricity (a generator in range); without it it is just a pipe.
- **Heat unit**: stands at a wall of a house (any of the four edges of its cell) on the end of a pipe. When hot water reaches it, every radiator within 10 cells of it works (three floors up and down; the radius is the sandbox option `InletRadius`) - no pipes inside the house.
- **Radiators** stand in the rooms, at any of the four walls. A working one warms the air around it the way a vanilla fireplace does (an `IsoHeatSource`): walls and closed doors stop the heat. They start to warm at 30 degrees of water and give full heat at 80.
- Fuel: an idle boiler burns 1 unit a game hour, plus 0.05 for every radiator it feeds; a log is 6 units, the furnace holds 500.

## Building

Everything is built from the context menu on the ground, **Heating**; a placed thing has its own menu (state in the tooltip, *Check the supply*, *Take apart*).

- **Players** craft the parts (crafting tab *Heating*, welding) and need a **pipe wrench** on them. Placing takes the part and a little time; taking a thing apart gives the part back. Nothing can be built or taken apart in somebody else's safehouse. Sandbox `PlayersBuild` turns this off.
- **Radiators** are anybody's to put in and take out. **Everything else** - pipes, heat units, pump stations, water intakes, boiler houses - is built and taken apart only by the head and staff of an organization with the **Heat supply** activity. An admin ticks it in the organization window of Delirium Economy, the same way as *Road repair* of Delirium Roads. Other players see those parts greyed out in the menu with the reason. Lighting a boiler and loading fuel stay open to everyone.
- **Admins** build for free and at once, and can fill a boiler with fuel or water.
- *Pipe here*, or a run: *Pipe run: start here* on one cell, then *Pipe run: lay to here* on another (along x, then along y; up to 200 cells; cells already taken are passed over). The next run starts where the last one ended. *Remove pipes to here* takes a run off.
- *Radiator here* and *Heat unit here* (at the north, west, south or east wall of the cell), *Pump station here*, *Water intake* (the clicked cell is its near corner), *Boiler house* (front to the south or to the east; the clicked cell is the middle of the front).

The objects cannot be picked up or broken with a sledgehammer.

| Recipe | Skill | Ingredients (plus a welding mask) |
|---|---|---|
| 3 heating pipes | Welding 2 | 1 sheet metal, 1 torch use |
| Radiator | Welding 2 | 4 small sheet metal, 2 metal pipes, 2 torch uses |
| Heat unit | Welding 3 | 2 sheet metal, 4 metal pipes, 6 nuts and bolts, 3 torch uses |
| Pump station | Welding 4, Electrical 3 | 2 sheet metal, 2 metal pipes, 2 metal bars, engine parts, 4 electric wire, 10 scrap electronics, 10 screws, 4 torch uses |
| Water intake kit | Welding 5, Electrical 4 | 6 sheet metal, 6 metal pipes, 4 metal bars, 2 engine parts, 2 rubber hoses, 6 electric wire, 15 scrap electronics, 20 screws, 8 torch uses |
| Boiler house kit | Welding 7 | 20 sheet metal, 10 metal pipes, 10 metal bars, 60 clay bricks, 20 nuts and bolts, 10 torch uses |

## Sandbox options (page DelHeat)

| Option | Default | Meaning |
|---|---|---|
| `PlayersBuild` | true | players build with crafted parts (radiators anyone, the rest a heat supply organization); off - admins only |
| `FuelCapacity` | 500 | fuel units a boiler house holds; one unit is one game hour of an idle boiler |
| `BurnPerHour` | 1 | units a lit boiler burns each game hour |
| `BurnPerRadiator` | 0.05 | extra units per hour for every radiator fed |
| `HeatUpPerMinute` | 1 | water heats up, degrees per game minute |
| `CoolDownPerMinute` | 0.25 | water cools down, degrees per game minute |
| `WaterCapacity` | 1000 | litres in a boiler's tank |
| `WaterPerHour` | 10 | litres a burning boiler loses each game hour |
| `WaterPerRadiator` | 0.5 | extra litres per hour for every radiator fed |
| `IntakeRate` | 200 | litres a working intake adds to a boiler each game hour |
| `IntakeReach` | 60 | cells of pipe the water travels from an intake |
| `BoilerReach` | 40 | cells of pipe the hot water travels from a boiler house |
| `PumpReach` | 80 | cells a working pump sends it further |
| `PumpNeedsPower` | true | pumps and intakes work only on a powered square |
| `InletRadius` | 10 | cells around a heat unit in which radiators work |
| `RadiatorTemp` | 35 | air temperature at a radiator at full heat (a fireplace is 35) |
| `RadiatorRadius` | 6 | cells at which the heat fades to nothing |
| `PetrolPerLitre` | 2 | units per litre of petrol, 0 to refuse petrol |
| `FuelTable` | `Base.Log:6; Base.Firewood:2; Base.Plank:2; ...; Base.PropaneTank:80` | item:units pairs |

Tiles: pack `delheat`, `tiledef=delheat 1919`. Art is modelled from primitives and rendered with the PZ camera: `art/render_heat.py` (Blender) -> `art/cut_heat.py` (frames, item icons, `art/tiles.json`) -> `tools/TilePack/build-tilepack.ps1`. Translations are written by `art/make_translations.py`.
